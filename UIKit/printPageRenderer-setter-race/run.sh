#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Builds and runs this method's repro.m, then writes a results/ record via
# make-crash-result.sh. Run from this directory. Prints "RESULT_FILE
# <path>" as its last line so callers (run-in-tart.sh, track.yml) can
# locate the file it wrote without guessing the OS build in its name.
#
# The crash is a same-process race, like DeviceCheck's: 8 threads hammer
# the setter within one process, so one cold run and one warm run suffice.
# The cold run is expected to crash, so it runs outside `set -e` and its
# exit code is captured rather than treated as a script failure.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)
sdk=$(xcrun --sdk macosx --show-sdk-path)

clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -framework Foundation -framework UIKit "$here/repro.m" -o "$here/repro"

set +e
"$here/repro" 10000 > "$here/cold.out" 2>&1
cold_exit=$?
"$here/repro" 50000 warm > "$here/warm.out" 2>&1
warm_exit=$?
set -e

{
    date -u +%Y-%m-%dT%H:%M:%SZ
    sw_vers
    echo "race cold rounds=10000 exit=$cold_exit"
    cat "$here/cold.out"
    echo "race warm rounds=50000 exit=$warm_exit"
    cat "$here/warm.out"
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt"

result_line=$("$here/../../scripts/make-crash-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/cold.out" "$here/warm.out" "$here/repro"
echo "RESULT_FILE $result_file"
