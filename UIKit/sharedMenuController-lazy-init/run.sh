#!/bin/sh
# run.sh <platform-label> [xcode-version]
#
# The cold trial runs once per process (the slot's slow path is one-shot
# per process), so it is retried as fresh child processes until the first
# nonzero exit or MAX_COLD_ATTEMPTS. Prints "RESULT_FILE <path>" as the
# last line for run-in-tart.sh and track.yml.
set -eu

platform="$1"
xcode_version="${2:-}"
here=$(cd "$(dirname "$0")" && pwd)
max_cold_attempts=50

sdk=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi \
    -isysroot "$sdk" \
    -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" \
    -framework Foundation -framework UIKit \
    "$here/repro.m" -o "$here/repro"

attempts=0
cold_exit=0
cold_out=
set +e
while [ "$attempts" -lt "$max_cold_attempts" ]; do
    attempts=$((attempts + 1))
    cold_out=$("$here/repro" cold 2>&1)
    cold_exit=$?
    [ "$cold_exit" -ne 0 ] && break
done
warm_out=$("$here/repro" warm 2>&1)
warm_exit=$?
set -e

{
    date -u +%Y-%m-%dT%H:%M:%SZ
    sw_vers
    echo "race cold rounds=$attempts exit=$cold_exit"
    if [ -n "$cold_out" ]; then
        printf '%s\n' "$cold_out"
    fi
    echo "race warm rounds=1 exit=$warm_exit"
    if [ -n "$warm_out" ]; then
        printf '%s\n' "$warm_out"
    fi
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt"

result_line=$("$here/../../scripts/make-crash-result.sh" "$platform" "$here/output.txt" "$here/results" "clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/repro"
echo "RESULT_FILE $result_file"
