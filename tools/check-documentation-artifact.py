#!/usr/bin/env python3
"""Validate the native Common Lisp API artifact and its source identity."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

from api_directory import fold


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / "docs" / "_build" / "api.json"
SHA = re.compile(r"^[0-9a-f]{40}$")


def git(*args: str) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=ROOT, text=True
    ).strip()


def require(condition: object, message: str) -> None:
    if not condition:
        raise SystemExit(f"documentation artifact: {message}")


require(ARTIFACT.is_file(), "missing docs/_build/api.json")
artifact = json.loads(ARTIFACT.read_text())
source = artifact.get("source", {})
exporter = artifact.get("exporter", {})
library = artifact.get("library", {})
runtime = artifact.get("runtime", {})
packages = artifact.get("packages", [])
files = source.get("files", [])

require(artifact.get("schema") == "libtmux.lisp.api/1", "unsupported schema")
require(artifact.get("port") == "lisp", "wrong port")
require(source.get("repository") == "libtmux/libtmux-lisp", "wrong repository")
require(source.get("revision") == git("rev-parse", "HEAD"), "stale source revision")
require(isinstance(source.get("dirty"), bool), "source dirty state is missing")
require(exporter.get("name") == "libtmux.documentation", "wrong exporter")
require(exporter.get("version") == 1, "wrong exporter version")
require(SHA.fullmatch(exporter.get("revision", "")), "invalid exporter revision")
require(isinstance(exporter.get("dirty"), bool), "exporter dirty state is missing")
require(library.get("version") == "0.1.0", "wrong ASDF system version")
require(runtime.get("implementation") == "SBCL", "wrong Lisp implementation")
require(runtime.get("implementationVersion"), "missing Lisp implementation version")
require(runtime.get("asdfVersion") == "3.3.7", "wrong ASDF producer version")

file_paths = [entry.get("path") for entry in files]
require(file_paths == sorted(set(file_paths)), "source files are not sorted and unique")
require("tools/documentation.lisp" in file_paths, "exporter source is absent")
for entry in files:
    path = ROOT / entry["path"]
    require(path.is_file(), f"missing source file {entry['path']}")
    require(
        hashlib.sha256(path.read_bytes()).hexdigest() == entry.get("sha256"),
        f"stale source hash for {entry['path']}",
    )

tracked_dirty = bool(git("status", "--porcelain", "--", *file_paths))
exporter_dirty = bool(
    git("status", "--porcelain", "--", "tools/documentation.lisp")
)
require(source["dirty"] == tracked_dirty, "source dirty state is stale")
require(exporter["dirty"] == exporter_dirty, "exporter dirty state is stale")

package_names = [package.get("name") for package in packages]
require(
    package_names
    == [
        "libtmux",
        "libtmux.control",
        "libtmux.json",
        "libtmux.query",
        "libtmux.workspace",
        "libtmux.workspace.cli",
    ],
    "public package inventory differs",
)

symbols = [symbol for package in packages for symbol in package.get("symbols", [])]
ids = [symbol.get("id") for symbol in symbols]
require(len(ids) == len(set(ids)), "duplicate public symbol identity")
required = {
    "libtmux.control:open-connection",
    "libtmux.control:await-request",
    "libtmux.control:next-event",
    "libtmux:fetch-snapshot",
    "libtmux:window-link",
    "libtmux.query:compile-filter",
    "libtmux.json:read-filter",
    "libtmux.workspace:apply-workspace",
    "libtmux.workspace.cli:main",
}
require(required <= set(ids), "required public declarations are absent")
require(not any("internal" in identity for identity in ids), "private symbols escaped")
require(not any("mcp" in identity for identity in ids), "excluded MCP API escaped")

provenance = set(file_paths)
for symbol in symbols:
    require(symbol.get("kind") in {"function", "class", "exception"}, f"invalid kind for {symbol.get('id')}")
    require(symbol.get("name"), f"missing name for {symbol.get('id')}")
    require(symbol.get("documentation", {}).get("summary"), f"missing summary for {symbol.get('id')}")
    location = symbol.get("source", {})
    require(location.get("file") in provenance, f"untracked source for {symbol.get('id')}")
    require(isinstance(location.get("line"), int) and location["line"] > 0, f"missing source line for {symbol.get('id')}")
    source = (ROOT / location["file"]).read_text()
    declaration = re.compile(
        rf"^[ \t]*\((?:defun|defmacro|defgeneric|defmethod|defclass|define-condition)[ \t]+"
        rf"(?:[\w.+-]+::?)?{re.escape(symbol['name'])}(?=[\s(])",
        re.IGNORECASE | re.MULTILINE,
    )
    declaration_lines = {
        source.count("\n", 0, match.start()) + 1 for match in declaration.finditer(source)
    }
    if declaration_lines:
        require(
            location["line"] in declaration_lines,
            f"source line does not name {symbol.get('id')}",
        )
    if symbol["kind"] == "function":
        require(symbol.get("signature"), f"missing native signature for {symbol.get('id')}")
        if symbol.get("generic"):
            require(symbol.get("methods"), f"missing CLOS methods for {symbol['id']}")
            for method in symbol["methods"]:
                require(method.get("signature"), f"missing method signature for {symbol['id']}")
                require(isinstance(method.get("qualifiers"), list),
                        f"missing method qualifiers for {symbol['id']}")
                require(all(target == "common-lisp:t" or target in ids
                            for target in method.get("specializers", [])),
                        f"non-public method specializer for {symbol['id']}")

panes = symbols[ids.index("libtmux:panes")]
require(
    {tuple(method["specializers"]) for method in panes.get("methods", [])}
    == {("libtmux:snapshot",), ("libtmux:window/type",)},
    "pane traversal lost snapshot/window method applicability",
)
field_value = symbols[ids.index("libtmux:field-value")]
require(
    [method["specializers"] for method in field_value.get("methods", [])]
    == [["libtmux:entity", "common-lisp:t"]],
    "field lookup lost its unspecialized second required argument",
)

apply_workspace = symbols[ids.index("libtmux.workspace:apply-workspace")]
require(
    "libtmux.workspace:result-outcomes"
    in apply_workspace["documentation"].get("seeAlso", []),
    "authored API cross-reference was not preserved",
)

cli = symbols[ids.index("libtmux.workspace.cli:main")]
require(
    {"libtmux.workspace:apply-workspace", "libtmux:outcome-status", "libtmux:outcome-phase"}
    <= set(cli["documentation"].get("seeAlso", [])),
    "workspace CLI lost authored references to another public package",
)
client = symbols[ids.index("libtmux:client")]
runs, strays = fold(client["documentation"].get("body", ""))
require(len(runs) == 1 and not strays,
        "libtmux:client lost its capability directory: need three or more bold-led "
        f"paragraphs, each followed by a references-only paragraph (folded {len(runs)}, "
        f"left as prose {strays})")
listed = {reference for _, references in runs[0] for reference in references}
require(listed <= set(ids), f"directory references unknown symbols: {sorted(listed - set(ids))}")
operations = {
    symbol["id"] for symbol in symbols
    if symbol["kind"] == "function" and symbol["id"].startswith("libtmux:")
    and re.match(r"^\([^ )]+ client[ )]", symbol["signature"])
}
require(operations <= listed,
        f"operations that take a client are missing from the directory: {sorted(operations - listed)}")

workspace_reference = (ROOT / "docs/workspace-api.md").read_text()
for anchor in ("outcome-status-function", "outcome-phase-function"):
    require(f"(api.md#{anchor})" in workspace_reference,
            f"workspace reference does not link the core {anchor}")

print(
    "Native Common Lisp documentation artifact: PASS "
    f"({len(packages)} packages, {len(symbols)} declarations, {len(files)} inputs)"
)
