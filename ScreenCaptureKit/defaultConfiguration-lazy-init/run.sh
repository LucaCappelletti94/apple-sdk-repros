#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Prints "RESULT_FILE <path>" as its last line so callers can locate the record.
# The target's slow path is one-shot per process, so each cold trial is a fresh child process.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)

clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit "$here/repro.m" -o "$here/repro"

set +e
cold_exit=0
attempts=0
while [ "$attempts" -lt 50 ] && [ "$cold_exit" -eq 0 ]; do
    attempts=$((attempts + 1))
    "$here/repro" cold > "$here/cold.out" 2>&1
    cold_exit=$?
done
"$here/repro" warm > "$here/warm.out" 2>&1
warm_exit=$?
set -e

{
    date -u +%Y-%m-%dT%H:%M:%SZ
    sw_vers
    echo "race cold rounds=$attempts exit=$cold_exit"
    cat "$here/cold.out"
    echo "race warm rounds=1 exit=$warm_exit"
    cat "$here/warm.out"
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt"

result_line=$("$here/../../scripts/make-crash-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/cold.out" "$here/warm.out" "$here/repro"
echo "RESULT_FILE $result_file"
