#!/bin/sh
# make-nullability-result.sh <platform-label> <output-file> <dest-dir> <command> [xcode-version]
# Writes one results/ record at `fault` strength from a header-nullability harness's output.
# Verdict is `reproduced` when a NULL reached a parameter the header declares nonnull.
set -eu

platform="$1"
output="$2"
dest="$3"
command="$4"
xcode_version="${5:-}"

build=$(grep '^BuildVersion:' "$output" | awk '{print $2}')
product_version=$(grep '^ProductVersion:' "$output" | awk '{print $2}')
if [ -z "$build" ]; then
    echo "make-nullability-result.sh: no BuildVersion line found in $output" >&2
    exit 1
fi

mkdir -p "$dest"
dest_file="$dest/${platform}-${build}.json"

python3 - "$platform" "$product_version" "$build" "$xcode_version" "$command" "$output" "$dest_file" <<'PYEOF'
import json, re, sys

platform, product_version, build, xcode_version, command, output_path, dest_path = sys.argv[1:8]
text = open(output_path).read()

header = None
m = re.search(r'^header old_result=(\S+) new_result=(\S+)$', text, re.M)
if m:
    header = {"old_result": m.group(1), "new_result": m.group(2)}

runs = []
for m in re.finditer(r'^added=(\d+) added_with_null_old=(\d+) removed=(\d+) removed_with_null_new=(\d+) other=(\d+)$', text, re.M):
    added, added_null, removed, removed_null, other = map(int, m.groups())
    runs.append({
        "added": added,
        "added_with_null_old": added_null,
        "removed": removed,
        "removed_with_null_new": removed_null,
        "other": other,
    })

def violated(r):
    return (header["old_result"] == "nonnull" and r["added_with_null_old"] > 0) or \
        (header["new_result"] == "nonnull" and r["removed_with_null_new"] > 0)

if header is None or not runs:
    verdict = "inconclusive"
elif any(violated(r) for r in runs):
    verdict = "reproduced"
elif any(r["added"] > 0 and r["removed"] > 0 for r in runs):
    verdict = "not-reproduced"
else:
    verdict = "inconclusive"

record = {
    "platform": platform,
    "os": {"product_version": product_version, "build": build},
    "xcode_version": xcode_version or None,
    "command": command,
    "strength": "fault",
    "header": header,
    "runs": runs,
    "verdict": verdict,
    "raw_output": text,
}

with open(dest_path, "w") as f:
    json.dump(record, f, indent=2, sort_keys=False)
    f.write("\n")
print(f"wrote {dest_path}: verdict={verdict}")
PYEOF
