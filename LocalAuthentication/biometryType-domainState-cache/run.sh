#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Builds and runs this method's repro.m, then writes a results/ record via
# make-race-window-result.sh. Run from this directory. Prints
# "RESULT_FILE <path>" as its last line so callers (run-in-tart.sh,
# track.yml) can locate the file it wrote without guessing the OS build
# in its name.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)

clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication "$here/repro.m" -o "$here/repro"
{
    date -u +%Y-%m-%dT%H:%M:%SZ
    sw_vers
    "$here/repro" 8 4 5
    "$here/repro" 8 4 5
    "$here/repro" 8 4 5
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt" 2>&1

result_line=$("$here/../../scripts/make-race-window-result.sh" "$platform" "$here/output.txt" "$here/results" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/repro"
echo "RESULT_FILE $result_file"
