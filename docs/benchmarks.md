# Measure subprocess and control costs

The benchmark compares the same literal reads through the native Lisp library.
It measures snapshot acquisition separately. It is a performance tool, outside
CI and the inner/mid/outer test loops.

## Run a comparison

Use the [supported SBCL/Linux profile](transport.md#supported-process-boundary)
and the checkout's pinned mise toolchain. No Qlot packages or optional regex/JSON
libraries are required. From the checkout root:

```console
$ mise run benchmark
```

`LIBTMUX_TEST_TMUX` selects a native tmux binary; otherwise the runner resolves
`tmux` on PATH. To reproduce the current stable cell, first use the
[cached provisioning instructions](testing.md), then run:

```console
$ LIBTMUX_TEST_TMUX=build/tmux/bin/3.8/tmux mise run benchmark
```

The default fixture has four `/bin/cat` panes. Each read sample returns eight
256-byte literal lines. The runner performs three warmup rounds and 20 measured
rounds, rotating phase order. It checks every returned byte and snapshot pane
count, then proves the owned daemon and children have stopped.

Each invocation creates a fresh durable directory under `dist/benchmarks/`.
`records.tsv` contains native measurements, `run.log` retains diagnostics and
`report.json` records source hashes, tool/runtime identities, samples and resource
usage. A failed or partial run remains `FAIL`; it does not produce a comparison.
A common benchmark lock prevents simultaneous runs from this project's checkouts.
The existing test-only subreaper applies its 60-second whole-run bound and checks
for owned descendants. Reduce the shape if it cannot complete within that bound.

A smaller diagnostic run deliberately omits p95 because it has fewer than 20
samples:

```console
$ mise run benchmark -- --samples 6 --commands 2 --panes 2
```

## What each phase measures

- `subprocess`: eight serial [`run-command`](api.md#run-command-function) reads,
  each with its own supervised process.
- `control-serial`: eight [`submit-command`](control-api.md#submit-command-function)
  calls, each followed by [`await-request`](control-api.md#await-request-function).
- `control-queued`: submit all eight requests on the same connection, then await
  each result. One worker still serializes execution; this is queueing, not
  concurrent tmux command execution.
- `snapshot`: one [`fetch-snapshot`](api.md#fetch-snapshot-function), with a checked
  physical pane count. A graph acquisition is a different workload from a
  literal read; do not compare their totals as transport speedups.

The optional control feature requires an actual daemon at least 3.7. On 3.3a the
report explicitly records control as unsupported and measures available phases.
Core support remains the complete tmux 3.3a–3.8 range. Benchmarks do not expand or
replace compatibility qualification.

Session/pane creation (`setup.fixture`) and control open/close are outside
steady-state samples and timed separately. Control startup includes preflight
and attachment. Daemon/client opening and fixture shutdown are verified but not
individually timed; whole-run elapsed also includes Lisp startup, compilation,
warmup and harness overhead. Client launch counts come from the native process
hook and exclude the separately owned daemon process and Python driver. The
reporter checks one launch per subprocess read and zero for persistent control;
snapshot launch counts remain observational. A completed read means command-queue
completion, without an application-readiness claim.

## Read the report

Latency is per complete phase batch, measured by SBCL's monotonic clock API.
Clock units are nanoseconds; that does not promise nanosecond accuracy. The
ordinary Lisp elapsed-time counter was too coarse for the smallest control
batches on the measured host; the runner rejects zero-duration samples.

`bytes_consed` is the delta of SBCL's process-wide allocation counter. It includes
worker allocation, counter overhead and normal GC behavior; it is not live heap
retention. `result_bytes` counts delivered application payload, excluding reply
guards, completion markers and other wire overhead. Graph captures leave this
field unknown. Source hashes bind the actual library and harness; extracted
archives report their content hashes without inventing a Git revision.

Each phase reports a median and a deterministic 2,000-resample percentile
bootstrap interval. p95 uses nearest rank and appears only with at least 20
samples. A read-path ratio appears only when the median intervals do not
overlap; otherwise it is `unresolved`. These are exploratory single-host
observations, affected by scheduling and shared load, rather than performance
bounds. Inspect CPU busy percentage, load, available memory and disk before
interpreting a run. Compare phases individually and include startup for short
lived connections.

This small fixture does not establish large-server scaling, stream throughput,
retained-graph memory cost or reconnect behavior. Those remain separate work.
See the [native workload](../tools/benchmark.lisp),
[reporter](../tools/benchmark.py), [control guide](control.md) and
[verification coverage](../verification.md).
