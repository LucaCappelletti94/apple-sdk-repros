#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Builds and runs this method's repro.m, then writes a results/ record via
# make-crash-result.sh. Run from this directory. Prints "RESULT_FILE
# <path>" as its last line so callers (run-in-tart.sh, track.yml) can
# locate the file it wrote without guessing the OS build in its name.
#
# The cold run is expected to crash, so it runs outside `set -e` and its
# exit code is captured rather than treated as a script failure.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)

clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit "$here/repro.m" -o "$here/repro"

set +e
cold_exit=0
attempts=0
while [ "$attempts" -lt 5 ] && [ "$cold_exit" -eq 0 ]; do
    attempts=$((attempts + 1))
    "$here/repro" 3000 > "$here/cold.out" 2>&1
    cold_exit=$?
done
"$here/repro" 3000 warm > "$here/warm.out" 2>&1
warm_exit=$?
set -e

{
    date -u +%Y-%m-%dT%H:%M:%SZ
    sw_vers
    echo "race cold rounds=3000 exit=$cold_exit"
    cat "$here/cold.out"
    echo "race warm rounds=3000 exit=$warm_exit"
    cat "$here/warm.out"
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt"

result_line=$("$here/../../scripts/make-crash-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/cold.out" "$here/warm.out" "$here/repro"
echo "RESULT_FILE $result_file"
