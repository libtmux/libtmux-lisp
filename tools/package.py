#!/usr/bin/env python3
"""Build the source artifact and load it without project or optional libraries."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--examples", action="store_true", help="Also run archived examples on owned tmux servers")
arguments = parser.parse_args()
started = time.monotonic()
output = root / "dist"
output.mkdir(exist_ok=True)
archive = output / "libtmux-source.tar.gz"
sources = [root / name for name in ("libtmux.asd", "LICENSE", "README.md", "qlfile", "qlfile.lock",
                                   "mise.toml", ".tool-versions", "AGENTS.md", "verification.md")]
sources += sorted((root / "src").rglob("*.lisp"))
sources += sorted((root / "tests").rglob("*.lisp"))
sources += sorted((root / "tests").rglob("*.py"))
sources += sorted((root / "docs").rglob("*.md"))
sources += sorted((root / "data").glob("*.json"))
sources += sorted(path for path in (root / "examples").iterdir() if path.is_file())
sources += sorted(path for path in (root / "tools").iterdir() if path.is_file())
sources += sorted(path for path in (root / ".github").rglob("*") if path.is_file())
epoch = int(os.environ.get("SOURCE_DATE_EPOCH") or subprocess.check_output(
    ["git", "show", "-s", "--format=%ct", "HEAD"], cwd=root, text=True).strip())


def archive_metadata(info):
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    info.mtime = epoch
    return info


with archive.open("wb") as stream, gzip.GzipFile(fileobj=stream, filename="", mode="wb", mtime=epoch) as compressed:
    with tarfile.open(fileobj=compressed, mode="w") as tar:
        for path in sources:
            tar.add(path, arcname=Path("libtmux") / path.relative_to(root), filter=archive_metadata)
asdf = subprocess.check_output(["mise", "where", "http:asdf-lisp"], cwd=root, text=True).strip()
with tempfile.TemporaryDirectory(prefix="libtmux-lisp-consumer-") as directory:
    destination = Path(directory)
    with tarfile.open(archive) as tar:
        tar.extractall(destination, filter="data")
    environment = os.environ.copy()
    environment["CL_SOURCE_REGISTRY"] = f'(:source-registry (:directory "{destination}/libtmux/") :ignore-inherited-configuration)'
    environment["ASDF_OUTPUT_TRANSLATIONS"] = f'(:output-translations (t "{destination}/fasl/") :ignore-inherited-configuration)'
    subprocess.run([
        "sbcl", "--noinform", "--no-sysinit", "--no-userinit", "--non-interactive",
        "--load", str(Path(asdf) / "asdf.lisp"),
        "--eval", '(require :asdf)',
        "--eval", '(asdf:load-system "libtmux")',
        "--eval", '(assert (find-package :libtmux))',
        "--eval", '(assert (not (find-package :cl-ppcre)))',
        "--eval", '(assert (not (find-package :com.inuoe.jzon)))',
        "--eval", '(assert (not (find-package :bt2)))',
    ], cwd=destination, env=environment, check=True)
    if arguments.examples:
        extracted = destination / "libtmux"
        subprocess.run(["python3", str(extracted / "tools/doc-examples.py")],
                       cwd=extracted, env=environment, check=True)
        subprocess.run(["python3", str(extracted / "tools/test-processes.py"), "python3",
                        str(extracted / "tools/examples.py")],
                       cwd=root, env=environment, check=True)
        shutil.copyfile(extracted / "dist/examples-evidence.json", output / "examples-evidence.json")
evidence = {"artifact": archive.name, "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "elapsed_seconds": round(time.monotonic() - started, 3), "core_consumer": "PASS"}
if arguments.examples:
    evidence["archived_examples"] = "PASS"
(output / "package-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
print(json.dumps(evidence))
