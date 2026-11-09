#!/usr/bin/env python3
"""Compare native subprocess/control reads; retain checked samples outside CI."""
import argparse
import csv
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import time


def summarize(values):
    """Summarize >=6 observations; deterministic median bootstrap, no sparse tail."""
    values = sorted(values)
    if len(values) < 6 or any(not math.isfinite(x) or x < 0 for x in values):
        raise ValueError("Need at least six finite nonnegative observations")
    rng = random.Random(0)
    medians = sorted(statistics.median(rng.choices(values, k=len(values))) for _ in range(2000))
    return {"samples": len(values), "median": statistics.median(values),
            "median_ci95": [medians[49], medians[1949]],
            "p95": values[math.ceil(0.95 * len(values)) - 1] if len(values) >= 20 else None}


def validate_samples(samples, phases, count):
    """Refuse partial, duplicate or unexpected sample coordinates."""
    coordinates = [(sample["phase"], sample["iteration"]) for sample in samples]
    expected = {(phase, i) for phase in phases for i in range(count)}
    if len(coordinates) != len(expected) or set(coordinates) != expected:
        raise ValueError("Incomplete, duplicate or unexpected benchmark samples")


def compare(left, right):
    """Claim a ratio only for separated median intervals of the same workload."""
    a, b = left["median_ci95"], right["median_ci95"]
    separated = a[0] > b[1] or b[0] > a[1]
    return {"status": "separated" if separated else "unresolved",
            "ratio": left["median"] / right["median"] if separated and right["median"] else None}


def resources():
    memory = dict(line.split(":", 1) for line in Path("/proc/meminfo").read_text().splitlines())
    return {"load_average": os.getloadavg(), "cpu_count": os.cpu_count(),
            "cpu_ticks": list(map(int, Path("/proc/stat").read_text().splitlines()[0].split()[1:9])),
            "available_memory_kib": int(memory["MemAvailable"].split()[0]),
            "free_disk_bytes": shutil.disk_usage(Path.cwd()).free}


def read_records(path, count, commands):
    metadata, samples, timings, clean = {}, [], [], False
    with path.open() as stream:
        records = list(csv.reader(stream, delimiter="\t"))
    for record in records:
        if len(record) == 3 and record[0] == "meta":
            if record[1] in metadata:
                raise ValueError("Duplicate benchmark metadata")
            metadata[record[1]] = record[2]
        elif record == ["cleanup", "fixture", "PASS"]:
            if clean:
                raise ValueError("Duplicate cleanup receipt")
            clean = True
        elif len(record) == 7 and record[0] in ("sample", "setup", "cleanup"):
            _, phase, iteration, seconds, allocated, launches, result_bytes = record
            value = {"phase": phase, "iteration": int(iteration), "seconds": float(seconds),
                     "bytes_consed": int(allocated), "client_launches": int(launches),
                     "result_bytes": None if result_bytes == "-" else int(result_bytes)}
            if not math.isfinite(value["seconds"]) or any(value[key] < 0 for key in
                    ("seconds", "bytes_consed", "client_launches")):
                raise ValueError("Invalid benchmark measurement")
            (samples if record[0] == "sample" else timings).append(value)
        else:
            raise ValueError("Unknown benchmark record")
    if not clean or not all(metadata.get(key) for key in ("sbcl", "asdf", "tmux", "control", "clock", "clock-units-per-second")):
        raise ValueError("Missing runtime or cleanup evidence")
    if metadata["control"] not in ("available", "unsupported-before-3.7"):
        raise ValueError("Unknown control qualification")
    phases = ["subprocess", "snapshot"]
    if metadata["control"] == "available":
        phases += ["control-serial", "control-queued"]
    validate_samples(samples, phases, count)
    expected_timings = {"fixture"} | ({"control-open", "control-close"} if metadata["control"] == "available" else set())
    if len(timings) != len(expected_timings) or {timing["phase"] for timing in timings} != expected_timings:
        raise ValueError("Missing, duplicate or unexpected setup/cleanup measurements")
    for sample in samples:
        if sample["seconds"] <= 0:
            raise ValueError("Sample is below clock resolution")
        if sample["phase"] == "snapshot":
            if sample["result_bytes"] is not None:
                raise ValueError("Snapshot does not expose application reply bytes")
        elif sample["result_bytes"] != commands * 257:
            raise ValueError("Read lanes did not return the same workload")
        if sample["phase"] == "subprocess" and sample["client_launches"] != commands:
            raise ValueError("Subprocess launch counter does not match the workload")
        if sample["phase"].startswith("control-") and sample["client_launches"] != 0:
            raise ValueError("Persistent control unexpectedly launched a client")
    return metadata, samples, timings


def source_identity(root):
    """Bind a checkout or extracted archive to its actual runtime source bytes."""
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=root, text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    checkout = top.returncode == 0 and Path(top.stdout.strip()).resolve() == root
    names = ["libtmux.asd", "tools/benchmark.py", "tools/benchmark.lisp", "tools/test-processes.py"]
    names += [str(path.relative_to(root)) for path in sorted((root / "src").glob("*.lisp"))]
    return {"source_kind": "checkout" if checkout else "archive-or-unversioned",
            "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() if checkout else None,
            "source_dirty": bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=root)) if checkout else None,
            "source_sha256": {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in names}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--program", default=os.environ.get("LIBTMUX_TEST_TMUX", "tmux"))
    parser.add_argument("--samples", type=int, choices=range(6, 201), default=20, metavar="6..200")
    parser.add_argument("--commands", type=int, choices=range(1, 33), default=8, metavar="1..32")
    parser.add_argument("--panes", type=int, choices=range(1, 17), default=4, metavar="1..16")
    parser.add_argument("--output", type=Path, help="New durable evidence directory; defaults to dist/benchmarks/run-*")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    program = shutil.which(args.program)
    if program is None:
        parser.error("Select a native tmux binary with --program")
    program = Path(program).resolve()
    lock_path = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "libtmux-lisp/benchmark.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("Another libtmux-lisp benchmark is running")
        if args.output:
            directory = args.output.resolve()
            directory.mkdir(parents=True, exist_ok=False)
        else:
            base = root / "dist/benchmarks"
            base.mkdir(parents=True, exist_ok=True)
            directory = Path(tempfile.mkdtemp(prefix=datetime.now(timezone.utc).strftime("run-%Y%m%dT%H%M%S-"), dir=base))
        started = time.monotonic()
        report = {"status": "FAIL", "workload": {"samples": args.samples, "commands": args.commands,
                  "panes": args.panes, "payload_bytes": 256, "warmup_rounds": 3},
                  **source_identity(root),
                  "tmux_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
                  "host": {"system": os.uname().sysname, "kernel": os.uname().release, "architecture": os.uname().machine},
                  "before": resources(), "statistics": {"bootstrap_resamples": 2000, "seed": 0,
                    "interval": "percentile 95% median", "tail": "nearest rank p95, at least 20 observations",
                    "latency_unit": "one complete phase batch"}}
        try:
            asdf = Path(subprocess.check_output(["mise", "where", "http:asdf-lisp"], cwd=root, text=True).strip()) / "asdf.lisp"
            environment = os.environ.copy()
            for key in ("TMUX", "TMUX_PANE"):
                environment.pop(key, None)
            command = [sys.executable, str(root / "tools/test-processes.py"), "sbcl",
                       "--noinform", "--no-sysinit", "--no-userinit", "--load", str(asdf),
                       "--script", str(root / "tools/benchmark.lisp"), str(program),
                       str(args.samples), str(args.commands), str(args.panes), str(directory / "records.tsv")]
            with (directory / "run.log").open("w") as log:
                result = subprocess.run(command, cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT)
            report["exit_code"] = result.returncode
            if result.returncode:
                raise RuntimeError("Native benchmark or owned-residue check failed; inspect run.log")
            metadata, samples, timings = read_records(directory / "records.tsv", args.samples, args.commands)
            report.update(runtime=metadata, samples=samples, setup_cleanup=timings)
            report["phases"] = {
                phase: {key: summarize([sample[key] for sample in samples if sample["phase"] == phase])
                        for key in ("seconds", "bytes_consed", "client_launches")}
                for phase in sorted({sample["phase"] for sample in samples})}
            report["comparisons"] = {lane: compare(report["phases"]["subprocess"]["seconds"], report["phases"][lane]["seconds"])
                                     for lane in ("control-serial", "control-queued") if lane in report["phases"]}
            report["status"] = "PASS"
            report["owned_residue"] = "NONE"
        except Exception as error:
            report["error"] = str(error)
        finally:
            report.update(after=resources(), elapsed_seconds=round(time.monotonic() - started, 3))
            ticks = [end - start for start, end in zip(report["before"]["cpu_ticks"], report["after"]["cpu_ticks"])]
            report["host_busy_percent"] = round(100 * (1 - (ticks[3] + ticks[4]) / sum(ticks)), 2) if sum(ticks) else None
            (directory / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": report["status"], "evidence": directory.name,
                          "elapsed_seconds": report["elapsed_seconds"]}))
        return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
