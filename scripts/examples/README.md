# examples

Runs the shipped examples and the tutorial against owned tmux daemons. Two
groups run as separate supervised children: `core` (assertions, tutorial,
quickstart, workspace command line, managed daemon, pane operations,
configuration, and control on tmux 3.8 or newer) and `owned-workspace`. Each
example starts and stops its own daemon through the library. Evidence goes to
`dist/examples-evidence.json`.

```console
$ mise run examples
```

`LIBTMUX_TEST_TMUX` selects a native tmux binary.
`tests/example-cleanup.lisp` proves that a failure injected into the tutorial
keeps its original error and leaves no daemon; `mise run integration` runs it.
Tests: `mise run scripts`.
