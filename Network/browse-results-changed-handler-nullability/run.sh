#!/bin/sh
# run.sh <platform-label> [xcode-version] [sim-udid] [sim-product-version] [sim-build-version]
# Probes the SDK header, runs repro.m, writes a results/ record and prints "RESULT_FILE <path>" last.
# An "ios-simulator-*" label builds for the iPhone Simulator SDK and runs on the booted simulator sim-udid.
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
        target_flags="-target arm64-apple-ios17.0-simulator -isysroot $sdk"
        command_str="clang -O2 -fobjc-arc -target arm64-apple-ios17.0-simulator -isysroot \$(xcrun --sdk iphonesimulator --show-sdk-path) -framework Foundation -framework Network repro.m -o repro"
        run_repro() { xcrun simctl spawn "$sim_udid" "$here/repro"; }
        version_block() {
            printf 'ProductName:\t\tiOS Simulator\n'
            printf 'ProductVersion:\t\t%s\n' "$sim_product_version"
            printf 'BuildVersion:\t\t%s\n' "$sim_build_version"
        }
        ;;
    *)
        target_flags=""
        command_str="clang -O2 -fobjc-arc -framework Foundation -framework Network repro.m -o repro"
        run_repro() { "$here/repro"; }
        version_block() { sw_vers; }
        ;;
esac

probe_compile() {
    # shellcheck disable=SC2086  # target_flags is a list of separate arguments
    clang -fsyntax-only -fobjc-arc -Werror=nonnull $target_flags "$@" "$here/repro.m"
}

# Without a probe macro the file must compile cleanly, so a nonnull error below comes from the probe.
probe_compile

# Prints nonnull or not-nonnull for the parameter the given PROBE_* macro passes NULL to.
annotation() {
    if probe_compile -D"$1" > "$here/probe.out" 2>&1; then
        echo not-nonnull
    elif grep -q 'requires a non-null argument' "$here/probe.out"; then
        echo nonnull
    else
        cat "$here/probe.out" >&2
        exit 1
    fi
}
old_annotation=$(annotation PROBE_OLD_RESULT)
new_annotation=$(annotation PROBE_NEW_RESULT)

# shellcheck disable=SC2086  # target_flags is a list of separate arguments
clang -O2 -fobjc-arc $target_flags -framework Foundation -framework Network "$here/repro.m" -o "$here/repro"

started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
set +e
run_repro > "$here/repro.out" 2>&1
repro_exit=$?
set -e

{
    echo "$started"
    version_block
    echo "header old_result=$old_annotation new_result=$new_annotation"
    echo "repro exit=$repro_exit"
    cat "$here/repro.out"
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$here/output.txt"

result_line=$("$here/../../scripts/make-nullability-result.sh" "$platform" "$here/output.txt" "$here/results" "$command_str" "$xcode_version")
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^wrote \(.*\): verdict=.*/\1/p')
rm -f "$here/output.txt" "$here/probe.out" "$here/repro.out" "$here/repro"
echo "RESULT_FILE $result_file"
