#!/bin/sh
# run-in-tart.sh <method-dir> <tart-image> [cache-budget-gb]
#
# Pulls (if needed) and boots a tart macOS image, copies <method-dir>/repro.m
# into it, builds and runs it the same way track.yml does, copies the output
# back, and writes a results/ record via make-result.sh.
#
# Caps the OCI image cache at <cache-budget-gb> (default 150GB, room for the
# three tracked majors at ~50GB each per architecture.md decision 7) with
# tart's own `prune --entries caches --space-budget`, which evicts the
# least-recently-used image first. Run on the Mac that has tart installed
# (currently ~/.local/tart on pippo).
set -eu

method_dir="$1"
image="$2"
cache_budget_gb="${3:-150}"

tart="$HOME/.local/tart/tart.app/Contents/MacOS/tart"
vm_name="apple-sdk-repros-$(basename "$image" | tr ':/' '--')"

"$tart" prune --entries caches --space-budget "$cache_budget_gb"

if ! "$tart" list --quiet --source local 2>/dev/null | grep -qx "$vm_name"; then
    "$tart" clone "$image" "$vm_name"
fi

"$tart" run --no-graphics "$vm_name" &
trap '"$tart" stop "$vm_name" 2>/dev/null || true' EXIT
"$tart" ip "$vm_name" --wait 180 >/dev/null

method_name=$(basename "$method_dir")
"$tart" exec "$vm_name" mkdir -p "/tmp/$method_name"
"$tart" exec -i "$vm_name" sh -c "cat > /tmp/$method_name/repro.m" < "$method_dir/repro.m"

"$tart" exec "$vm_name" sh -c "
    set -e
    cd /tmp/$method_name
    clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication repro.m -o repro
    {
        date -u +%Y-%m-%dT%H:%M:%SZ
        sw_vers
        ./repro direct 1 16000000
        for i in 1 2 3; do ./repro direct 16 1000000; done
        for i in 1 2 3 4 5 6 7 8 9 10; do ./repro new 8 3000; done
        date -u +%Y-%m-%dT%H:%M:%SZ
    } > output.txt 2>&1
"
"$tart" exec "$vm_name" cat "/tmp/$method_name/output.txt" > "/tmp/$method_name-output.txt"

platform_label="macos-vm-tart-$(basename "$image" | sed 's/:.*//')"
"$HOME/github/apple-sdk-repros/scripts/make-result.sh" "$platform_label" "/tmp/$method_name-output.txt" "$method_dir/results"
rm -f "/tmp/$method_name-output.txt"

echo "done; VM '$vm_name' left stopped and resident for the next run"
