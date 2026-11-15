# benchmark

Reporter for the optional transport benchmark. It runs the workload in
`tools/benchmark.lisp` under `scripts/test-processes`, validates its records,
summarizes each phase with a deterministic bootstrap of the median and writes
`report.json`, `records.tsv` and `run.log` to a new directory (default
`dist/benchmarks/run-*`). A ratio is claimed only for separated intervals.

```console
$ mise run benchmark
```

Options: `--program`, `--samples 6..200`, `--commands 1..32`, `--panes 1..16`,
`--output DIR`. See [benchmarks](../../docs/benchmarks.md). Tests:
`mise run scripts`.
