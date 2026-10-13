#!/bin/sh
# run-in-ios-simulator.sh <method-dir> <runtime-identifier> [device-type-name]
#
# Boots (or reuses) an iOS Simulator device for the given runtime, builds
# and runs the method's own repro.m there via its run.sh's ios-simulator
# mode, and copies the results/ record it writes back out. Method-agnostic
# in the same spirit as run-in-tart.sh, but unlike that script there is no
# remote host to copy files to or from: the simulator is a local process
# on this same Mac, so it only needs the device's identity and the
# runtime's own version/build, both read from `simctl` itself rather than
# trusted from a label.
#
# runtime-identifier is a full `com.apple.CoreSimulator.SimRuntime.*`
# identifier, as listed by `xcrun simctl list runtimes`. device-type-name
# defaults to "iPhone 17 Pro" (any modern, always-available device type);
# override it if that type is not installed for the given runtime.
set -eu

method_dir="$1"
runtime_id="$2"
device_type="${3:-iPhone 17 Pro}"

runtime_json=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
runtimes = json.load(sys.stdin)['runtimes']
for r in runtimes:
    if r['identifier'] == '$runtime_id':
        print(r['version'])
        print(r['buildversion'])
        break
else:
    sys.exit('runtime not found: $runtime_id')
")
sim_product_version=$(echo "$runtime_json" | sed -n '1p')
sim_build_version=$(echo "$runtime_json" | sed -n '2p')
if [ -z "$sim_product_version" ] || [ -z "$sim_build_version" ]; then
    echo "run-in-ios-simulator.sh: could not resolve runtime $runtime_id" >&2
    exit 1
fi

sim_udid=$(xcrun simctl list devices "$runtime_id" -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices'].get('$runtime_id', [])
for d in devices:
    if d['name'] == '$device_type' and d['isAvailable']:
        print(d['udid'])
        break
")
if [ -z "$sim_udid" ]; then
    sim_udid=$(xcrun simctl create "apple-sdk-repros-$device_type" "$device_type" "$runtime_id")
fi

state=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for runtime_devices in json.load(sys.stdin)['devices'].values():
    for d in runtime_devices:
        if d['udid'] == '$sim_udid':
            print(d['state'])
            sys.exit()
")
we_booted_it=0
if [ "$state" != "Booted" ]; then
    xcrun simctl boot "$sim_udid"
    we_booted_it=1
fi
if [ "$we_booted_it" = 1 ]; then
    trap 'xcrun simctl shutdown "$sim_udid" 2>/dev/null || true' EXIT
fi

platform_label="ios-simulator-$sim_product_version"
xcode_version=$(xcodebuild -version | head -1 | awk '{print $2}')

result_line=$(cd "$method_dir" && ./run.sh "$platform_label" "$xcode_version" "$sim_udid" "$sim_product_version" "$sim_build_version" | tail -1)
result_file=$(printf '%s\n' "$result_line" | sed -n 's/^RESULT_FILE //p')
if [ -z "$result_file" ]; then
    echo "run-in-ios-simulator.sh: run.sh did not print a RESULT_FILE line" >&2
    exit 1
fi
echo "done: $result_file"
