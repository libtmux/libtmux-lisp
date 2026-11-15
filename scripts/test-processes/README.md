# test-processes

Runs a command in its own process group and fails when it leaves descendants.
The script becomes a subreaper, waits up to 60 seconds, then kills and counts
every process the command orphaned. The exit status is the command's, or 1 when
a descendant survived. `mise run integration` wraps each suite in it; the
library never does.

```console
$ mise exec -- sbcl --script scripts/test-processes/test-processes.lisp \
    sbcl --script tools/test.lisp integration
```

`tests/child.lisp` holds the child programs that the process and pane tests
start. Tests: `mise run scripts`.
