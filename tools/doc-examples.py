#!/usr/bin/env python3
"""Keep Markdown excerpts identical to the executable Lisp examples; check local links."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
write = sys.argv[1:] == ["write"]
source = "\n".join(path.read_text() for path in sorted((root / "examples").glob("*.lisp")))
snippets = dict(re.findall(r"^;;; docs:(\w+)\n(.*?)^;;; docs:end$", source, re.M | re.S))
errors = []
for path in [root / "README.md", *sorted(path for path in (root / "docs").rglob("*.md") if "_build" not in path.relative_to(root / "docs").parts)]:
    text = path.read_text()
    def replace(match):
        name = match.group(1)
        if name not in snippets:
            raise RuntimeError(f"Unknown executable excerpt {name}")
        return f"<!-- example:{name} -->\n```lisp\n{snippets[name].rstrip()}\n```\n<!-- /example -->"
    expected = re.sub(r"<!-- example:(\w+) -->.*?<!-- /example -->", replace, text, flags=re.S)
    if expected != text:
        if write:
            path.write_text(expected)
            text = expected
        else:
            errors.append(f"Stale example excerpt: {path.relative_to(root)}")
    for target in re.findall(r"(?<!!)\[[^\]]+\]\(([^)]+)\)", text):
        if "://" in target or target.startswith("mailto:"):
            continue
        location, _, anchor = target.partition("#")
        destination = (path.parent / location).resolve() if location else path
        if not destination.exists():
            errors.append(f"Broken local link in {path.relative_to(root)}: {target}")
        elif anchor and destination.suffix == ".md":
            body = destination.read_text()
            headings = re.findall(r"^#+ (.+)$", body, re.M)
            anchors = {re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-") for heading in headings}
            anchors.update(re.findall(r'<a id="([^"]+)"', body))
            if anchor not in anchors:
                errors.append(f"Broken local anchor in {path.relative_to(root)}: {target}")
if errors:
    raise SystemExit("\n".join(errors))
print("Executable excerpts and local documentation links: PASS")
