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
rows = []

for readme in sorted(glob.glob(os.path.join(root, "*", "*", "README.md"))):
    method_dir = os.path.dirname(readme)
    framework = os.path.basename(os.path.dirname(method_dir))
    method = os.path.basename(method_dir)

    text = open(readme).read()
    m = re.search(r"Apple Feedback:\s*(FB\d+)", text)
    fb = m.group(1) if m else "none filed"

    verdicts = set()
    for result_path in sorted(glob.glob(os.path.join(method_dir, "results", "*.json"))):
        with open(result_path) as f:
            verdicts.add(json.load(f)["verdict"])

    if not verdicts:
        status = "no results yet"
    elif "reproduced" in verdicts:
        status = "reproduced"
    elif verdicts == {"not-reproduced"}:
        status = "not reproduced"
    else:
        status = "inconclusive"

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
