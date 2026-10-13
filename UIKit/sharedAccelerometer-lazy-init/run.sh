#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# Builds and runs this method's repro.m, then writes a results/ record via
# make-crash-result.sh. Run from this directory. Prints "RESULT_FILE
# <path>" as its last line so callers (run-in-tart.sh, track.yml) can
# locate the file it wrote without guessing the OS build in its name.
#
# The lazy-init is one-shot per process, so every cold trial needs a fresh
# child process. The cold loop runs up to 50 fresh cold trials and stops at
# the first nonzero exit. The cold trial's exit code is captured rather
# than treated as a script failure.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)
sdk=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk

clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -framework Foundation -framework UIKit "$here/repro.m" -o "$here/repro"

set +e
cold_exit=0
attempts=0
for i in $(seq 1 50); do
    attempts=$i
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
    echo "race warm rounds=1 exit=$warm_exit"
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt"

result_line=$("$here/../../scripts/make-crash-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/cold.out" "$here/warm.out" "$here/repro"
echo "RESULT_FILE $result_file"
