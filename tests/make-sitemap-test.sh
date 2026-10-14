#!/bin/sh
# tests/make-sitemap-test.sh
#
# Regression test for scripts/make-sitemap.sh's Status column, which must
# lead with the strongest strength and, within it, a positive verdict over
# inconclusive over a negative one. Run from the repo root:
# sh tests/make-sitemap-test.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/scripts"
cp "$root/scripts/make-sitemap.sh" "$tmp/scripts/"
printf '# demo\n\n<!-- sitemap:start -->\n<!-- sitemap:end -->\n' > "$tmp/README.md"

# method <name> <strength:verdict>...
method() {
    dir="$tmp/Demo/$1"
    shift
    mkdir -p "$dir/results"
    printf '# demo method\n\nApple Feedback: not yet filed.\n' > "$dir/README.md"
    i=0
    for pair in "$@"; do
        i=$((i + 1))
        printf '{"strength": "%s", "verdict": "%s"}\n' "${pair%%:*}" "${pair#*:}" > "$dir/results/run$i.json"
    done
}

method mixed fault:inconclusive fault:reproduced fault:not-reproduced
method unsure fault:not-reproduced fault:inconclusive
method stronger dynamic-window:window-detected fault:not-reproduced

sh "$tmp/scripts/make-sitemap.sh" >/dev/null

fail=0
check() {
    got=$(grep "(Demo/$1/)" "$tmp/README.md" | awk -F' [|] ' '{print $3}')
    if [ "$got" != "$2" ]; then
        echo "FAIL $1: expected status '$2', got '$got'" >&2
        fail=1
    else
        echo "ok $1: $got"
    fi
}

check mixed "fault: reproduced"
check unsure "fault: inconclusive"
check stronger "fault: not-reproduced"

[ "$fail" = 0 ] && echo "make-sitemap-test.sh: all checks passed"
exit "$fail"
