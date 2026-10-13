#!/bin/sh
# run.sh <platform-label> [xcode-version] [sim-udid] [sim-product-version] [sim-build-version]
#
# Builds and runs this method's repro.m, then writes a results/ record via
# make-result.sh. Run from this directory. Prints "RESULT_FILE <path>" as
# its last line so callers (run-in-tart.sh, run-in-ios-simulator.sh, and
# track.yml) can locate the file it wrote without guessing the OS build
# in its name.
#
# A platform-label starting with "ios-simulator" builds for the iOS
# Simulator target instead of this host's native macOS, and runs through
# `xcrun simctl spawn` on the booted simulator identified by sim-udid
# (required in that case, along with the simulator's own product/build
# version, since `sw_vers` on this host would report the host's macOS
# version, not the simulated iOS one). Any other platform-label builds
# and runs natively, unchanged from before.
set -eu

platform="$1"
xcode_version="${2:-}"
sim_udid="${3:-}"
sim_product_version="${4:-}"
sim_build_version="${5:-}"
here=$(cd "$(dirname "$0")" && pwd)

case "$platform" in
    ios-simulator-*)
        if [ -z "$sim_udid" ] || [ -z "$sim_product_version" ] || [ -z "$sim_build_version" ]; then
            echo "run.sh: ios-simulator platform requires sim-udid, sim-product-version, and sim-build-version" >&2
            exit 1
        fi
        sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
        clang -O2 -fobjc-arc -target arm64-apple-ios17.0-simulator -isysroot "$sdk" -framework Foundation -framework LocalAuthentication "$here/repro.m" -o "$here/repro"
        run_repro() { xcrun simctl spawn "$sim_udid" "$here/repro" "$@"; }
        version_block() {
            printf 'ProductName:\t\tiOS Simulator\n'
            printf 'ProductVersion:\t\t%s\n' "$sim_product_version"
            printf 'BuildVersion:\t\t%s\n' "$sim_build_version"
        }
        ;;
    *)
        clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication "$here/repro.m" -o "$here/repro"
        run_repro() { "$here/repro" "$@"; }
        version_block() { sw_vers; }
        ;;
esac

{
    date -u +%Y-%m-%dT%H:%M:%SZ
    version_block
    run_repro direct 1 16000000
    # shellcheck disable=SC2034  # loop variable only counts repetitions
    for i in 1 2 3; do run_repro direct 16 1000000; done
    # shellcheck disable=SC2034  # loop variable only counts repetitions
    for i in 1 2 3; do run_repro new 8 3000; done
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt" 2>&1

case "$platform" in
    ios-simulator-*)
        command_str="clang -O2 -fobjc-arc -target arm64-apple-ios17.0-simulator -isysroot \$(xcrun --sdk iphonesimulator --show-sdk-path) -framework Foundation -framework LocalAuthentication repro.m -o repro"
        ;;
    *)
        command_str="clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication repro.m -o repro"
        ;;
esac
result_line=$("$here/../../scripts/make-result.sh" "$platform" "$here/output.txt" "$here/results" "$command_str" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/repro"
echo "RESULT_FILE $result_file"
