#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Builds, retries the cold trial in fresh processes up to 50 times
# (the slot fills once per process, so one process is one trial), then
# runs the warm control once, then writes a results/ record via
# make-crash-result.sh. Run from this directory. Prints "RESULT_FILE
# <path>" as its last line so callers can locate the file it wrote.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)

clang -O2 -fobjc-arc -framework Foundation "$here/repro.m" -o "$here/repro"

cold_exit=0
set +e
for attempt in $(seq 1 50); do
    "$here/repro" cold > "$here/cold.out" 2>&1
    cold_exit=$?
    [ "$cold_exit" -ne 0 ] && break
done
set -e

set +e
"$here/repro" warm > "$here/warm.out" 2>&1
warm_exit=$?
set -e

{
    date -u +%Y-%m-%dT%H:%M:%SZ
    sw_vers
    echo "race cold rounds=$attempt exit=$cold_exit"
    cat "$here/cold.out"
    echo "race warm rounds=1 exit=$warm_exit"
    cat "$here/warm.out"
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt"

result_line=$("$here/../../scripts/make-crash-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -framework Foundation repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/cold.out" "$here/warm.out" "$here/repro"
echo "RESULT_FILE $result_file"
