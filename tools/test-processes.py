#!/usr/bin/env python3
"""Reap descendants of this isolated integration image; never used by the library."""
import ctypes
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys

libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(36, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "Cannot enable the test-only subreaper")
process = subprocess.Popen(sys.argv[1:], start_new_session=True)
result = 1
try:
    result = process.wait(timeout=60)
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    leaked = []
    while True:
        try:
            pid, status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            break
        if pid:
            continue
        children = Path(f"/proc/self/task/{os.getpid()}/children").read_text().split()
        for child in children:
            try:
                fd = os.pidfd_open(int(child))
            except ProcessLookupError:
                continue
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(fd, selectors.EVENT_READ)
                    if not selector.select(0):
                        leaked.append(int(child))
                        signal.pidfd_send_signal(fd, signal.SIGKILL)
                    if not selector.select(0.5):
                        raise RuntimeError("Owned test descendant did not terminate")
                os.waitpid(int(child), 0)
            except ChildProcessError:
                pass
            finally:
                os.close(fd)
    if leaked:
        print(f"FAIL: {len(leaked)} owned descendants survived the test image", file=sys.stderr)
        result = 1
sys.exit(result)
