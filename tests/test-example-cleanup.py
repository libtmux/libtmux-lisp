#!/usr/bin/env python3
"""Prove a tutorial failure keeps its original error and reaps its owned daemon."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
environment = os.environ.copy()
environment["LIBTMUX_TEST_FAIL_TUTORIAL_BEFORE_TERMINATION"] = "1"
result = subprocess.run(
    [sys.executable, str(root / "tools/examples.py")],
    cwd=root,
    env=environment,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=30,
)
if result.returncode == 0:
    raise RuntimeError("The injected tutorial failure unexpectedly succeeded")
if "Injected tutorial failure before termination" not in result.stderr:
    raise RuntimeError("The tutorial runner replaced the injected failure")
if "Cleanup also failed" in result.stderr:
    raise RuntimeError("The tutorial runner did not clean up after the injected failure")
if result.stderr.count("Owned child exited 1; descendant cleanup: PASS") != 1:
    raise RuntimeError("The tutorial failure lacks successful descendant-cleanup evidence")
print("Tutorial failure cleanup and original error retention: PASS")
