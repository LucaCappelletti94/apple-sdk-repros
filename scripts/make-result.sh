#!/bin/sh
# make-result.sh <platform-label> <output-file> <dest-dir> [xcode-version]
#
# Turns a repro's raw stdout (expects `sw_vers` lines and `direct`/`new`
# result lines in the shape the LocalAuthentication repros print) into one
# results/<platform>-<build>.json record. Verdict is `reproduced` if any
# `new` line lost an increment, `not-reproduced` if every `new` and the
# single-threaded `direct 1 ...` control line lost none, `inconclusive`
# otherwise (for example if the control itself lost something).
set -eu

platform="$1"
output="$2"
dest="$3"
xcode_version="${4:-}"

build=$(grep '^BuildVersion:' "$output" | awk '{print $2}')
product_version=$(grep '^ProductVersion:' "$output" | awk '{print $2}')
if [ -z "$build" ]; then
    echo "make-result.sh: no BuildVersion line found in $output" >&2
    exit 1
fi

mkdir -p "$dest"
dest_file="$dest/${platform}-${build}.json"

python3 - "$platform" "$product_version" "$build" "$xcode_version" "$output" "$dest_file" <<'PYEOF'
import json, re, sys

platform, product_version, build, xcode_version, output_path, dest_path = sys.argv[1:7]
text = open(output_path).read()
lines = text.splitlines()

results = []
for l in lines:
    m = re.match(r'(direct|new): expected (\d+) increments, counter advanced (\d+), lost (\d+)', l)
    if m:
        results.append({
            "mode": m.group(1),
            "expected": int(m.group(2)),
            "advanced": int(m.group(3)),
            "lost": int(m.group(4)),
        })

control = [r for r in results if r["mode"] == "direct" and r["expected"] >= 1_000_000 and
           # the single-threaded control is the one whose expected count isn't
           # repeated by any 16-thread "direct" run in the same output
           sum(1 for r2 in results if r2["mode"] == "direct" and r2["expected"] == r["expected"]) == 1]
new_runs = [r for r in results if r["mode"] == "new"]

if not results:
    verdict = "inconclusive"
elif any(r["lost"] > 0 for r in control):
    verdict = "inconclusive"
elif any(r["lost"] > 0 for r in new_runs):
    verdict = "reproduced"
elif new_runs:
    verdict = "not-reproduced"
else:
    verdict = "inconclusive"

record = {
    "platform": platform,
    "os": {"product_version": product_version, "build": build},
    "xcode_version": xcode_version or None,
    "command": "clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication repro.m -o repro",
    "runs": results,
    "verdict": verdict,
    "raw_output": text,
}

with open(dest_path, "w") as f:
    json.dump(record, f, indent=2, sort_keys=False)
    f.write("\n")
print(f"wrote {dest_path}: verdict={verdict}")
PYEOF
