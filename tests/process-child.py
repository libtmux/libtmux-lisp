"""Deterministic process fixtures: readiness and signals, no polling sleeps."""
import os
import select
import signal
import sys


def block():
    reader, writer = os.pipe()
    os.read(reader, 1)


mode = sys.argv[1]
if mode == "duplex-input":
    os.write(1, bytes(range(256)) * 512)
    os.write(2, bytes(reversed(range(256))) * 512)
    while chunk := os.read(0, 65536):
        offset = 0
        while offset < len(chunk):
            offset += os.write(1, chunk[offset:])
elif mode == "bytes":
    os.write(1, bytes(range(256)))
elif mode == "argv":
    os.write(1, "\0".join(sys.argv[2:]).encode())
elif mode == "held-input":
    expected = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    data = b""
    while len(data) < expected:
        chunk = os.read(0, expected - len(data))
        if not chunk:
            raise RuntimeError("Premature input EOF")
        data += chunk
    poller = select.poll()
    poller.register(0, select.POLLIN | select.POLLHUP)
    if poller.poll(0):
        raise RuntimeError("Input retired before the child's natural completion")
    os.write(1, b"held:" + data)
elif mode == "failed":
    os.write(1, b"partial")
    os.write(2, b"failed")
    sys.exit(7)
elif mode == "exit":
    sys.exit(int(sys.argv[2]))
elif mode == "limit":
    while True:
        os.write(1, b"x" * 65536)
elif mode == "exact-limit":
    os.write(1, b"x" * 4096)
elif mode == "epipe":
    os.close(0)
    os.write(2, b"stdin closed")
    block()
elif mode == "ignore-term":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(sys.argv[2], "wb", buffering=0) as ready:
        ready.write(b"ready")
    block()
elif mode == "inherited-pipes":
    if os.fork():
        os._exit(0)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    os.write(2, b"inherited")
    block()
elif mode == "closed-pipes":
    reader, writer = os.pipe()
    if os.fork():
        os.close(writer)
        os.read(reader, 1)
        os._exit(0)
    os.close(reader)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    for descriptor in (0, 1, 2):
        os.close(descriptor)
    os.write(writer, b"ready")
    block()
elif mode == "wait":
    block()
else:
    raise ValueError(mode)
