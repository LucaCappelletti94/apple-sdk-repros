#!/bin/sh
# tests/make-result-test.sh
#
# Regression test for scripts/make-result.sh's verdict classification.
# Run from the repo root: sh tests/make-result-test.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0

check() {
    fixture="$1"
    expect_verdict="$2"
    expect_lines="$3"

    dest="$tmp/$fixture"
    "$root/scripts/make-result.sh" "test-$fixture" "$root/tests/fixtures/$fixture-output.txt" "$dest" "test-command-$fixture" >/dev/null

    file=$(ls "$dest"/*.json)
    got_verdict=$(python3 -c "import json; print(json.load(open('$file'))['verdict'])")
    got_lines=$(python3 -c "import json; print(len(json.load(open('$file'))['runs']))")
    got_strength=$(python3 -c "import json; print(json.load(open('$file'))['strength'])")
    got_command=$(python3 -c "import json; print(json.load(open('$file'))['command'])")

    if [ "$got_verdict" != "$expect_verdict" ]; then
        echo "FAIL $fixture: expected verdict '$expect_verdict', got '$got_verdict'" >&2
        fail=1
    elif [ "$got_lines" != "$expect_lines" ]; then
        echo "FAIL $fixture: expected $expect_lines parsed result lines, got $got_lines" >&2
        fail=1
    elif [ "$got_strength" != "fault" ]; then
        echo "FAIL $fixture: expected strength 'fault', got '$got_strength'" >&2
        fail=1
    elif [ "$got_command" != "test-command-$fixture" ]; then
        echo "FAIL $fixture: expected command 'test-command-$fixture', got '$got_command'" >&2
        fail=1
    else
        echo "ok $fixture: verdict=$got_verdict, strength=$got_strength, $got_lines result lines"
    fi
}

# A clean single-threaded control, a clean 16-thread direct run, and a
# clean "new" run: nothing lost anywhere, so the race did not reproduce.
check clean not-reproduced 3

# The single-threaded control itself lost an increment, which should never
# happen and means the run itself is suspect, not evidence either way.
check bad-control inconclusive 2

# Real captured output (macos-host-apple-silicon-25G83.json's raw_output):
# two of three "new" runs lost an increment, so this is a reproduction.
check reproduced reproduced 7

# Real captured output (an iOS Simulator run): every "new" run is clean
# but the repeated 16-thread "direct" runs lose millions of increments.
# This is the exact shape that exposed the bug where the classifier only
# ever looked at "new" runs for the reproduced signal, never at the
# non-control "direct" runs, silently reporting not-reproduced.
check direct-only-reproduced reproduced 7

if [ "$fail" != 0 ]; then
    echo "make-result-test.sh: one or more checks failed" >&2
    exit 1
fi
echo "make-result-test.sh: all checks passed"
