#!/bin/sh
# run-in-tart.sh <method-dir> <tart-image> [cache-budget-gb]
#
# Pulls (if needed) and boots a tart macOS image, copies <method-dir>'s
# repro.m and run.sh plus the repository's scripts/ into it at the same
# relative depth run.sh expects (../../scripts/...), runs run.sh there,
# and copies the results/ record it writes back out. Method-agnostic: it
# only knows the repro.m/run.sh convention every method directory
# follows, not any method's own build or invocation.
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

# A VM another invocation just stopped may still be mid-shutdown; starting
# it again too soon fails instead of queuing, so wait for it to actually
# reach a stable (stopped or running) state before deciding what to do.
we_started_it=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    state=$("$tart" list --format json --source local | python3 -c "
import json, sys
for vm in json.load(sys.stdin):
    if vm['Name'] == '$vm_name':
        print(vm['State'])
        break
")
    case "$state" in
        running) break ;;
        stopped)
            "$tart" run --no-graphics "$vm_name" &
            we_started_it=1
            break
            ;;
        *) sleep 5 ;;
    esac
done
if [ "$we_started_it" = 1 ]; then
    trap '"$tart" stop "$vm_name" 2>/dev/null || true' EXIT
fi
"$tart" ip "$vm_name" --wait 180 >/dev/null

# Mirror the repo's own layout under this root, so run.sh's relative
# ../../scripts/ reference resolves the same way it does in the real repo.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
remote_root="/tmp/apple-sdk-repros-vm"
remote_method_dir="$remote_root/$method_dir"

"$tart" exec "$vm_name" mkdir -p "$remote_method_dir/results" "$remote_root/scripts"
"$tart" exec -i "$vm_name" sh -c "cat > $remote_method_dir/repro.m" < "$method_dir/repro.m"
"$tart" exec -i "$vm_name" sh -c "cat > $remote_method_dir/run.sh && chmod +x $remote_method_dir/run.sh" < "$method_dir/run.sh"
for s in "$repo_root"/scripts/*.sh; do
    name=$(basename "$s")
    "$tart" exec -i "$vm_name" sh -c "cat > $remote_root/scripts/$name && chmod +x $remote_root/scripts/$name" < "$s"
done

platform_label="macos-vm-tart-$(basename "$image" | sed 's/:.*//')"
result_line=$("$tart" exec "$vm_name" sh -c "cd $remote_method_dir && ./run.sh '$platform_label'" | tail -1)
remote_result_file=$(printf '%s\n' "$result_line" | sed -n 's/^RESULT_FILE //p')
if [ -z "$remote_result_file" ]; then
    echo "run-in-tart.sh: run.sh did not print a RESULT_FILE line" >&2
    exit 1
fi

mkdir -p "$method_dir/results"
"$tart" exec "$vm_name" cat "$remote_result_file" > "$method_dir/results/$(basename "$remote_result_file")"

echo "done; VM '$vm_name' left stopped and resident for the next run"
