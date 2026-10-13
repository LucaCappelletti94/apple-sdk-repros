#!/bin/sh
# make-result.sh <platform-label> <output-file> <dest-dir> <command> [xcode-version]
#
# Turns a repro's raw stdout (expects `sw_vers` lines and `direct`/`new`
# result lines in the shape the LocalAuthentication repros print) into one
# results/<platform>-<build>.json record, at `fault` strength (see
# EVIDENCE.md): these runs either show the actual wrong answer or they
# don't, there is no weaker claim being made. The single-threaded `direct
# threads=1 ...` line is the control; verdict is `reproduced` if any
# other `direct` or `new` line lost an increment, `not-reproduced` if
# every other line lost none, `inconclusive` otherwise (for example if
# the control itself lost something, or there is nothing but the control
# to compare against).
set -eu

platform="$1"
output="$2"
dest="$3"
command="$4"
xcode_version="${5:-}"

build=$(grep '^BuildVersion:' "$output" | awk '{print $2}')
product_version=$(grep '^ProductVersion:' "$output" | awk '{print $2}')
if [ -z "$build" ]; then
    echo "make-result.sh: no BuildVersion line found in $output" >&2
    exit 1
fi

mkdir -p "$dest"
dest_file="$dest/${platform}-${build}.json"

python3 - "$platform" "$product_version" "$build" "$xcode_version" "$command" "$output" "$dest_file" <<'PYEOF'
import json, re, sys

platform, product_version, build, xcode_version, command, output_path, dest_path = sys.argv[1:8]
text = open(output_path).read()
lines = text.splitlines()

results = []
for l in lines:
    m = re.match(r'(direct|new): threads=(\d+) expected (\d+) increments, counter advanced (\d+), lost (\d+)', l)
    if m:
        results.append({
            "mode": m.group(1),
            "threads": int(m.group(2)),
            "expected": int(m.group(3)),
            "advanced": int(m.group(4)),
            "lost": int(m.group(5)),
        })

direct_runs = [r for r in results if r["mode"] == "direct"]
# the single-threaded control is the direct-mode run invoked with
# threads=1, distinct from every multi-threaded direct trial
control = [r for r in direct_runs if r["threads"] == 1]
repeated_direct = [r for r in direct_runs if r["threads"] != 1]
new_runs = [r for r in results if r["mode"] == "new"]

if not results:
    verdict = "inconclusive"
elif any(r["lost"] > 0 for r in control):
    verdict = "inconclusive"
elif any(r["lost"] > 0 for r in repeated_direct) or any(r["lost"] > 0 for r in new_runs):
    verdict = "reproduced"
elif repeated_direct or new_runs:
    verdict = "not-reproduced"
else:
    verdict = "inconclusive"

record = {
    "platform": platform,
    "os": {"product_version": product_version, "build": build},
    "xcode_version": xcode_version or None,
    "command": command,
    "strength": "fault",
    "runs": results,
    "verdict": verdict,
    "raw_output": text,
}

with open(dest_path, "w") as f:
    json.dump(record, f, indent=2, sort_keys=False)
    f.write("\n")
print(f"wrote {dest_path}: verdict={verdict}")
PYEOF
