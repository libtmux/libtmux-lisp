#!/usr/bin/env python3
"""Stop the interactive tutorial's owned daemon, then remove its known files."""
import os
from pathlib import Path
import selectors
import shutil
import stat
import subprocess
import sys

directory = Path(sys.argv[1]).resolve()
metadata = directory.stat()
if (directory.parent != Path("/tmp") or not directory.name.startswith("libtmux-lisp-demo-")
        or metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o700):
    raise SystemExit("Expected the private directory created by the tutorial")
program = shutil.which(os.environ.get("LIBTMUX_TEST_TMUX", "tmux"))
environment = os.environ.copy()
for key in ("TMUX", "TMUX_PANE"):
    environment.pop(key, None)
command = [program, "-S", str(directory / "tmux.sock"), "-N"]
pid = int(subprocess.check_output(command + ["display-message", "-p", "#{pid}"],
                                  env=environment, text=True, timeout=1).strip())
descriptor = os.pidfd_open(pid)
try:
    subprocess.run(command + ["kill-server"], env=environment, check=True, timeout=1)
    with selectors.DefaultSelector() as selector:
        selector.register(descriptor, selectors.EVENT_READ)
        if not selector.select(0.75):
            raise RuntimeError("The owned demo daemon did not exit")
finally:
    os.close(descriptor)
for filename in ("tmux.sock", "worker-receipt.txt"):
    (directory / filename).unlink(missing_ok=True)
directory.rmdir()
print("Demo daemon exited; owned files removed")
