#!/bin/sh
# tests/make-crash-result-test.sh
#
# Regression test for scripts/make-crash-result.sh's verdict
# classification. Run from the repo root: sh tests/make-crash-result-test.sh
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
    "$root/scripts/make-crash-result.sh" "test-$fixture" "$root/tests/fixtures/$fixture-output.txt" "$dest" "test-command-$fixture" >/dev/null

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

# Real captured output (DeviceCheck's macos-host-apple-silicon result):
# the cold run exited 139 (SIGSEGV), the warm control exited 0.
check crash-reproduced reproduced 2

# Both runs exit 0: the race did not crash this time.
check crash-not-reproduced not-reproduced 2

if [ "$fail" != 0 ]; then
    echo "make-crash-result-test.sh: one or more checks failed" >&2
    exit 1
fi
echo "make-crash-result-test.sh: all checks passed"
