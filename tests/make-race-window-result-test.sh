#!/bin/sh
# tests/make-race-window-result-test.sh
#
# Regression test for scripts/make-race-window-result.sh's verdict
# classification. Run from the repo root: sh tests/make-race-window-result-test.sh
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
    "$root/scripts/make-race-window-result.sh" "test-$fixture" "$root/tests/fixtures/$fixture-output.txt" "$dest" >/dev/null

    file=$(ls "$dest"/*.json)
    got_verdict=$(python3 -c "import json; print(json.load(open('$file'))['verdict'])")
    got_lines=$(python3 -c "import json; print(len(json.load(open('$file'))['runs']))")
    got_strength=$(python3 -c "import json; print(json.load(open('$file'))['strength'])")

    if [ "$got_verdict" != "$expect_verdict" ]; then
        echo "FAIL $fixture: expected verdict '$expect_verdict', got '$got_verdict'" >&2
        fail=1
    elif [ "$got_lines" != "$expect_lines" ]; then
        echo "FAIL $fixture: expected $expect_lines parsed result lines, got $got_lines" >&2
        fail=1
    elif [ "$got_strength" != "dynamic-window" ]; then
        echo "FAIL $fixture: expected strength 'dynamic-window', got '$got_strength'" >&2
        fail=1
    else
        echo "ok $fixture: verdict=$got_verdict, strength=$got_strength, $got_lines result lines"
    fi
}

# No run saw an overlap: the race window was not caught this time.
check no-window no-window-detected 2

# Real captured output (biometryType-domainState-cache's macos-host result):
# every run saw overlapping reader/writer intervals.
check window-detected window-detected 3

if [ "$fail" != 0 ]; then
    echo "make-race-window-result-test.sh: one or more checks failed" >&2
    exit 1
fi
echo "make-race-window-result-test.sh: all checks passed"
