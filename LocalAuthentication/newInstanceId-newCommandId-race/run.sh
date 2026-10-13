#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Builds and runs this method's repro.m, then writes a results/ record via
# make-result.sh. Run from this directory. Prints "RESULT_FILE <path>" as
# its last line so callers (run-in-tart.sh, track.yml) can locate the file
# it wrote without guessing the OS build in its name.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)

clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication "$here/repro.m" -o "$here/repro"
{
    date -u +%Y-%m-%dT%H:%M:%SZ
    sw_vers
    "$here/repro" direct 1 16000000
    # shellcheck disable=SC2034  # loop variable only counts repetitions
    for i in 1 2 3; do "$here/repro" direct 16 1000000; done
    # shellcheck disable=SC2034  # loop variable only counts repetitions
    for i in 1 2 3; do "$here/repro" new 8 3000; done
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt" 2>&1

result_line=$("$here/../../scripts/make-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/repro"
echo "RESULT_FILE $result_file"
