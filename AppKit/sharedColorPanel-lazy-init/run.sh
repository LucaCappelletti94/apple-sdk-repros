#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Builds and runs this method's repro.m, then writes a results/ record via
# make-crash-result.sh. Run from this directory. Prints "RESULT_FILE
# <path>" as its last line so callers (run-in-tart.sh, track.yml) can
# locate the file it wrote without guessing the OS build in its name.
#
# The slot's slow path runs once per process, so each trial is a fresh
# child process. Cold retries up to 50 fresh trials, stopping at the
# first divergence, then warm is one control trial.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)

clang -O2 -fobjc-arc -framework Foundation -framework AppKit "$here/repro.m" -o "$here/repro"

set +e
attempts=0
cold_exit=0
while [ "$attempts" -lt 50 ]; do
    attempts=$((attempts + 1))
    "$here/repro" cold > "$here/cold.out" 2>&1
    cold_exit=$?
    if [ "$cold_exit" -ne 0 ]; then
        break
    fi
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

result_line=$("$here/../../scripts/make-crash-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -framework Foundation -framework AppKit repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/cold.out" "$here/warm.out" "$here/repro"
echo "RESULT_FILE $result_file"
