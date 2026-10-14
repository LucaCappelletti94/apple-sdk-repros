#!/bin/sh
# track-all.sh <platform-label> [xcode-version] [per-method-timeout-seconds]
#
# Runs every <Framework>/<method>/run.sh in this repository one after
# another on this machine, the way track.yml's single job per runner image
# needs. Each method gets the timeout (default 900 seconds) before its whole
# process tree is killed, so one hanging method cannot stall the rest.
# Keeps going past failures, prints one line per method, and exits 1 at the
# end if any method failed or timed out.
set -u

platform="$1"
xcode_version="${2:-}"
limit="${3:-900}"
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

# macOS ships no `timeout`, so the watchdog kills children before parents.
kill_tree() {
    for child in $(pgrep -P "$1"); do
        kill_tree "$child"
    done
    kill -KILL "$1" 2>/dev/null
}

failed=0
for run in */*/run.sh; do
    method=$(dirname "$run")
    log="$root/$method/track.log"
    started=$(date +%s)
    (cd "$method" && exec ./run.sh "$platform" "$xcode_version") > "$log" 2>&1 &
    pid=$!
    timed_out=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ $(($(date +%s) - started)) -ge "$limit" ]; then
            kill_tree "$pid"
            timed_out=1
            break
        fi
        sleep 2
    done
    wait "$pid"
    rc=$?
    elapsed=$(($(date +%s) - started))

    if [ "$timed_out" = 1 ]; then
        echo "$method: TIMED OUT after ${elapsed}s"
    elif [ "$rc" -ne 0 ]; then
        echo "$method: FAILED with exit $rc after ${elapsed}s"
    else
        echo "$method: ok in ${elapsed}s, $(tail -1 "$log")"
        rm -f "$log"
        continue
    fi
    failed=$((failed + 1))
    tail -20 "$log" | sed 's/^/    /'
    rm -f "$log"
done

if [ "$failed" -gt 0 ]; then
    echo "track-all.sh: $failed method(s) failed or timed out" >&2
    exit 1
fi
