#!/bin/sh
# make-sitemap.sh
#
# Regenerates the method table in README.md between the
# <!-- sitemap:start --> / <!-- sitemap:end --> markers, from the
# repository's own <Framework>/<method>/{README.md,results/*.json}
# directories. Run after adding or retiring a method directory; ci.yml
# fails if this would produce a diff, so the table can't go stale.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

python3 - "$root" <<'PYEOF'
import glob, json, os, re, sys

root = sys.argv[1]
STRENGTH_ORDER = ["dynamic-window", "fault"]  # weakest to strongest of what results/ can hold
rows = []

for readme in sorted(glob.glob(os.path.join(root, "*", "*", "README.md"))):
    method_dir = os.path.dirname(readme)
    framework = os.path.basename(os.path.dirname(method_dir))
    method = os.path.basename(method_dir)

    text = open(readme).read()
    m = re.search(r"Apple Feedback:\s*(FB\d+)", text)
    fb = m.group(1) if m else "none filed"

    by_strength = {}
    for result_path in sorted(glob.glob(os.path.join(method_dir, "results", "*.json"))):
        with open(result_path) as f:
            r = json.load(f)
        by_strength.setdefault(r["strength"], set()).add(r["verdict"])

    if not by_strength:
        status = "no results yet"
    else:
        max_strength = max(by_strength, key=lambda s: STRENGTH_ORDER.index(s) if s in STRENGTH_ORDER else -1)
        verdicts = by_strength[max_strength]
        # a verdict that isn't phrased as a negative ("not-...", "no-...") is the
        # more newsworthy one to lead with when several runs disagree
        headline = next((v for v in sorted(verdicts) if not v.startswith(("not-", "no-"))), sorted(verdicts)[0])
        status = f"{max_strength}: {headline}"

    title = text.splitlines()[0].lstrip("# ").strip()
    rows.append((framework, title, method, fb, status))

lines = ["| Framework | Method | Status | Feedback |", "|---|---|---|---|"]
for framework, title, method, fb, status in rows:
    lines.append(f"| {framework} | [{title}]({framework}/{method}/) | {status} | {fb} |")
table = "\n".join(lines)

readme_path = os.path.join(root, "README.md")
content = open(readme_path).read()
start, end = "<!-- sitemap:start -->", "<!-- sitemap:end -->"
if start not in content or end not in content:
    sys.exit("make-sitemap.sh: README.md is missing the sitemap markers")
before = content[:content.index(start) + len(start)]
after = content[content.index(end):]
open(readme_path, "w").write(f"{before}\n{table}\n{after}")
print(f"wrote {len(rows)} row(s) to README.md")
PYEOF
