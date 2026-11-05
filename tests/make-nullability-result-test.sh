#!/bin/sh
# tests/make-nullability-result-test.sh
#
# Regression test for scripts/make-nullability-result.sh's verdict
# classification. Run from the repo root: sh tests/make-nullability-result-test.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0

check() {
    fixture="$1"
    expect_verdict="$2"
    expect_header="$3"

    dest="$tmp/$fixture"
    "$root/scripts/make-nullability-result.sh" "test-$fixture" "$root/tests/fixtures/$fixture-output.txt" "$dest" "test-command-$fixture" >/dev/null

    file=$(ls "$dest"/*.json)
    got_verdict=$(python3 -c "import json; print(json.load(open('$file'))['verdict'])")
    got_header=$(python3 -c "import json; h = json.load(open('$file'))['header']; print(h['old_result'], h['new_result'])")
    got_strength=$(python3 -c "import json; print(json.load(open('$file'))['strength'])")
    got_command=$(python3 -c "import json; print(json.load(open('$file'))['command'])")

    if [ "$got_verdict" != "$expect_verdict" ]; then
        echo "FAIL $fixture: expected verdict '$expect_verdict', got '$got_verdict'" >&2
        fail=1
    elif [ "$got_header" != "$expect_header" ]; then
        echo "FAIL $fixture: expected header '$expect_header', got '$got_header'" >&2
        fail=1
    elif [ "$got_strength" != "fault" ]; then
        echo "FAIL $fixture: expected strength 'fault', got '$got_strength'" >&2
        fail=1
    elif [ "$got_command" != "test-command-$fixture" ]; then
        echo "FAIL $fixture: expected command 'test-command-$fixture', got '$got_command'" >&2
        fail=1
    else
        echo "ok $fixture: verdict=$got_verdict, header=$got_header"
    fi
}

# Real captured output (macos-host-apple-silicon, 25G241): both parameters
# nonnull in the header, both NULLs passed at runtime.
check nullability-reproduced reproduced "nonnull nonnull"

# The same NULLs under a header that no longer says nonnull are no violation.
check nullability-header-fixed not-reproduced "not-nonnull not-nonnull"

# No service was seen, so the NULLs never had the chance to occur.
check nullability-no-events inconclusive "nonnull nonnull"

if [ "$fail" != 0 ]; then
    echo "make-nullability-result-test.sh: one or more checks failed" >&2
    exit 1
fi
echo "make-nullability-result-test.sh: all checks passed"
