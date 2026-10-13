#!/bin/sh
# make-crash-result.sh <platform-label> <output-file> <dest-dir> <command> [xcode-version]
#
# Turns a crash-style harness's raw stdout (lines of the shape
# "race <mode> rounds=N exit=E", as repro.m in
# DeviceCheck/appAttestController-lazy-init prints) into one
# results/<platform>-<build>.json record at `fault` strength (see
# EVIDENCE.md): the process either crashed or it didn't, there is no
# weaker claim being made. Verdict is `reproduced` if the harness's
# non-control ("cold") run exited abnormally, `not-reproduced` if every
# run exited 0, `inconclusive` otherwise (for example if the control run
# itself crashed, which should never happen).
set -eu

platform="$1"
output="$2"
dest="$3"
command="$4"
xcode_version="${5:-}"

build=$(grep '^BuildVersion:' "$output" | awk '{print $2}')
product_version=$(grep '^ProductVersion:' "$output" | awk '{print $2}')
if [ -z "$build" ]; then
    echo "make-crash-result.sh: no BuildVersion line found in $output" >&2
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
    m = re.match(r'race (\w+) rounds=(\d+) exit=(-?\d+)', l)
    if m:
        mode, rounds, exit_code = m.group(1), int(m.group(2)), int(m.group(3))
        runs.append({"mode": mode, "rounds": rounds, "exit_code": exit_code})

cold = [r for r in runs if r["mode"] == "cold"]
control = [r for r in runs if r["mode"] == "warm"]

if not runs:
    verdict = "inconclusive"
elif any(r["exit_code"] != 0 for r in control):
    verdict = "inconclusive"
elif any(r["exit_code"] != 0 for r in cold):
    verdict = "reproduced"
elif cold:
    verdict = "not-reproduced"
else:
    verdict = "inconclusive"

record = {
    "platform": platform,
    "os": {"product_version": product_version, "build": build},
    "xcode_version": xcode_version or None,
    "command": command,
    "strength": "fault",
    "runs": runs,
    "verdict": verdict,
    "raw_output": text,
}

with open(dest_path, "w") as f:
    json.dump(record, f, indent=2, sort_keys=False)
    f.write("\n")
print(f"wrote {dest_path}: verdict={verdict}")
PYEOF
