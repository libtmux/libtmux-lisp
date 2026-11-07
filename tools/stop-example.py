#!/usr/bin/env python3
"""Stop the interactive tutorial's retained daemon, then remove known files."""
import os
from pathlib import Path
import selectors
import shutil
import stat
import subprocess
import sys

arguments = sys.argv[1:]
already_terminated = arguments[:1] == ["--already-terminated"]
if already_terminated:
    arguments = arguments[1:]
if len(arguments) != 1:
    raise SystemExit("usage: stop-example.py [--already-terminated] DIRECTORY")
directory = Path(arguments[0]).resolve()
metadata = directory.stat()
if (directory.parent != Path("/tmp") or not directory.name.startswith("libtmux-lisp-demo-")
        or metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o700):
    raise SystemExit("Expected the private directory created by the tutorial")

witness_path = directory / "server-witness.txt"
parts = witness_path.read_text().split()
if len(parts) != 3 or not all(part.isdigit() for part in parts):
    raise RuntimeError("The tutorial server witness is malformed")
pid, socket_device, socket_inode = map(int, parts)
socket_path = directory / "tmux.sock"
recorded_identity = (socket_device, socket_inode)


def current_socket_identity():
    try:
        current = socket_path.stat()
    except FileNotFoundError:
        return None
    if not stat.S_ISSOCK(current.st_mode):
        raise RuntimeError("The tutorial endpoint is no longer a socket")
    return current.st_dev, current.st_ino


if current_socket_identity() not in (None, recorded_identity):
    raise RuntimeError("The tutorial endpoint was replaced")

descriptor = None
try:
    descriptor = os.pidfd_open(pid)
except ProcessLookupError:
    pass
process_alive = descriptor is not None
if descriptor is not None:
    with selectors.DefaultSelector() as selector:
        selector.register(descriptor, selectors.EVENT_READ)
        process_alive = not selector.select(0)

environment = os.environ.copy()
for key in ("TMUX", "TMUX_PANE"):
    environment.pop(key, None)
try:
    if process_alive and already_terminated:
        raise RuntimeError("The owned demo daemon is still running")
    if process_alive:
        program = shutil.which(os.environ.get("LIBTMUX_TEST_TMUX", "tmux"))
        if program is None:
            raise RuntimeError("tmux is required for cleanup")
        command = [program, "-S", str(socket_path), "-N"]
        live_pid = int(subprocess.check_output(command + ["display-message", "-p", "#{pid}"],
                                               env=environment, text=True, timeout=1).strip())
        if live_pid != pid or current_socket_identity() != recorded_identity:
            raise RuntimeError("The tutorial endpoint no longer identifies its retained daemon")
        subprocess.run(command + ["kill-server"], env=environment, check=True, timeout=1)
        with selectors.DefaultSelector() as selector:
            selector.register(descriptor, selectors.EVENT_READ)
            if not selector.select(0.75):
                raise RuntimeError("The owned demo daemon did not exit")
finally:
    if descriptor is not None:
        os.close(descriptor)

if current_socket_identity() not in (None, recorded_identity):
    raise RuntimeError("The tutorial endpoint changed during cleanup")
for filename in ("tmux.sock", "worker-receipt.txt", "server-witness.txt"):
    (directory / filename).unlink(missing_ok=True)
directory.rmdir()
print("Demo daemon is stopped; owned files removed")
