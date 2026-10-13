#!/bin/sh
# make-race-window-result.sh <platform-label> <output-file> <dest-dir> <command> [xcode-version]
#
# Turns a race-window harness's raw stdout (lines of the shape
# "readers=R writers=W seconds=S calls=C overlaps=N", as repro.m in
# LocalAuthentication/biometryType-domainState-cache prints) into one
# results/<platform>-<build>.json record at `dynamic-window` strength (see
# EVIDENCE.md): this proves the race window is live in a running process,
# not that anything was corrupted by it. Verdict is `window-detected` if
# any run saw at least one overlap, `no-window-detected` otherwise.
set -eu

platform="$1"
output="$2"
dest="$3"
command="$4"
xcode_version="${5:-}"

build=$(grep '^BuildVersion:' "$output" | awk '{print $2}')
product_version=$(grep '^ProductVersion:' "$output" | awk '{print $2}')
if [ -z "$build" ]; then
    echo "make-race-window-result.sh: no BuildVersion line found in $output" >&2
    exit 1
fi

mkdir -p "$dest"
dest_file="$dest/${platform}-${build}.json"

python3 - "$platform" "$product_version" "$build" "$xcode_version" "$command" "$output" "$dest_file" <<'PYEOF'
import json, re, sys

platform, product_version, build, xcode_version, command, output_path, dest_path = sys.argv[1:8]
text = open(output_path).read()

runs = []
for l in text.splitlines():
    m = re.match(r'readers=(\d+) writers=(\d+) seconds=(\d+) calls=(\d+) overlaps=(\d+)', l)
    if m:
        readers, writers, seconds, calls, overlaps = (int(x) for x in m.groups())
        runs.append({
            "readers": readers, "writers": writers, "seconds": seconds,
            "calls": calls, "overlaps": overlaps,
        })

verdict = "window-detected" if any(r["overlaps"] > 0 for r in runs) else "no-window-detected"
if not runs:
    verdict = "no-window-detected"

record = {
    "platform": platform,
    "os": {"product_version": product_version, "build": build},
    "xcode_version": xcode_version or None,
    "command": command,
    "strength": "dynamic-window",
    "runs": runs,
    "verdict": verdict,
    "raw_output": text,
}

with open(dest_path, "w") as f:
    json.dump(record, f, indent=2, sort_keys=False)
    f.write("\n")
print(f"wrote {dest_path}: verdict={verdict}")
PYEOF
