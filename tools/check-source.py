#!/usr/bin/env python3
"""Check owned source text without network, installs, or generated builds."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
names = subprocess.check_output(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
).decode().split("\0")
errors = []
for name in filter(None, names):
    path = root / name
    if path.is_symlink() or not path.is_file():
        continue
    if path.suffix not in {".lisp", ".asd", ".py", ".sh", ".md", ".toml", ".yml"}:
        continue
    data = path.read_text()
    for number, line in enumerate(data.splitlines(), 1):
        if line.rstrip() != line:
            errors.append(f"{name}:{number}: trailing whitespace")
    if data and not data.endswith("\n"):
        errors.append(f"{name}: missing final newline")
print("\n".join(errors) if errors else "Source checks passed")
sys.exit(bool(errors))
