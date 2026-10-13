#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Builds and runs this method's repro.m, then writes a results/ record via
# make-crash-result.sh. Run from this directory. Prints "RESULT_FILE
# <path>" as its last line so callers (run-in-tart.sh, track.yml) can
# locate the file it wrote without guessing the OS build in its name.
#
# The lazy-init race can only fire on the first call of a process, so
# each cold attempt is a fresh child process, retried up to COLD_MAX
# times; the first diverging attempt (nonzero exit) stops the loop.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)

COLD_MAX=50

clang -O2 -fobjc-arc -framework Foundation "$here/repro.m" -o "$here/repro"

cold_exit=0
cold_rounds=0
set +e
for i in $(seq 1 "$COLD_MAX"); do
    "$here/repro" cold > "$here/cold.out" 2>&1
    cold_exit=$?
    cold_rounds=$i
    [ "$cold_exit" -ne 0 ] && break
done
"$here/repro" warm > "$here/warm.out" 2>&1
warm_exit=$?
set -e

{
    date -u +%Y-%m-%dT%H:%M:%SZ
    sw_vers
    echo "race cold rounds=$cold_rounds exit=$cold_exit"
    cat "$here/cold.out"
    echo "race warm rounds=1 exit=$warm_exit"
    cat "$here/warm.out"
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt"

result_line=$("$here/../../scripts/make-crash-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -framework Foundation repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/cold.out" "$here/warm.out" "$here/repro"
echo "RESULT_FILE $result_file"
