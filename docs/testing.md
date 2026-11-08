# Testing

Use FiveAM directly at the REPL for local tests. Use the separate command for
live tmux tests so the process owner can check fixture cleanup.

## Run and redefine a local test

Install the pinned tools and locked dependencies following the
[contributor guide](../.github/CONTRIBUTING.md), then start a REPL:

```console
$ mise run repl
```

Load the unit tests:

```lisp
(asdf:load-system "libtmux/tests")
```

Run one existing test:

```lisp
(fiveam:run! 'libtmux.tests::record-codec-preserves-text-and-presence)
```

Re-evaluate its changed test definition in the editor, then rerun that name:

```lisp
(fiveam:!)
```

[`fiveam:!!`](https://github.com/lispci/fiveam/blob/3ba1300a9dd6bafdaef2af76d261d73bdf7e4bf0/src/run.lisp)
and [`fiveam:!!!`](https://github.com/lispci/fiveam/blob/3ba1300a9dd6bafdaef2af76d261d73bdf7e4bf0/src/run.lisp)
rerun the second and third previous selections.
These rerun functions do not shift their history. To enter the debugger on an
unexpected condition, run the test with `debug!`:

```lisp
(fiveam:debug! 'libtmux.tests::record-codec-preserves-text-and-presence)
```

FiveAM supplies `retest` and `ignore` restarts while the condition is active.
Use the complete unit suite after a focused change:

```lisp
(fiveam:run! 'libtmux.tests::unit)
```

Load and run the separate native-query suite without contacting tmux:

```lisp
(asdf:test-system "libtmux/query")
```

For interactive redefinition, load the test system explicitly:

```lisp
(asdf:load-system "libtmux/tests/query")
```

```lisp
(fiveam:run! 'libtmux.tests::query)
```

The optional systems keep their own suites and remain local:

```lisp
(asdf:test-system "libtmux/regex")
```

```lisp
(asdf:test-system "libtmux/json")
```

The pinned FiveAM 1.4.3 compiles test bodies at definition time by default.
After changing a macro used by a test, re-evaluate that test definition too.
For a test specifically studying macro redefinition, `def-test` supports the
`:compile-at :run-time` option. The upstream homepage's older macro-redefinition
description does not describe this default. See the pinned
[test definitions](https://github.com/lispci/fiveam/blob/3ba1300a9dd6bafdaef2af76d261d73bdf7e4bf0/src/test.lisp)
and [runner](https://github.com/lispci/fiveam/blob/3ba1300a9dd6bafdaef2af76d261d73bdf7e4bf0/src/run.lisp).

`run!` returns a Boolean; scripts must check it to return a failing process
status. Unknown names and entirely skipped selections can report no failures,
so select a known test or suite and read the check and skip counts. The shipped
runner selects declared suites and checks the result before exiting.

## Run external tests

Run all local checks without contacting tmux:

```console
$ mise run check
```

Run only the native-query inner loop:

```console
$ mise run query
```

Run the regex or JSON inner loop:

```console
$ mise run regex
```

```console
$ mise run json
```

Run the owned live fixtures with one explicit tmux executable:

```console
$ LIBTMUX_TEST_TMUX=/path/to/tmux mise run integration
```

This outer loop uses a dedicated process owner and subreaper. It checks that
no test-owned child or daemon survives the Lisp image. Tests coordinate through
FIFOs, semaphores, pidfds and application signals. A send acknowledgment alone
does not establish application consumption. See [verification](../verification.md)
for the loop budgets and current coverage.

## GitHub Actions

The workflow uses the same mise tasks, pinned SBCL/ASDF, Qlot lock and FiveAM
suites as local development. The supported tmux range is 3.3a through 3.8,
including every intermediate release. CI samples only the two endpoints to
reduce build time; that selection does not narrow compatibility. It uses one
language version: the latest stable SBCL pin in
[.tool-versions](../.tool-versions), currently 2.6.10. Pushes to `master`, pull
requests and manual runs check tmux 3.3a and 3.8. Unit tests cover
rejection of plain 3.3 without another tmux build. The explicit Ubuntu 26.04
image supplies the Linux capabilities required by the process backend.

Run the same endpoint checks manually:

```console
$ gh workflow run tests.yml \
    --ref master
```

Qlot dependencies use a cache keyed by the toolchain configuration and lock.
It contains both `.qlot` and Qlot's shared cache, because installed systems
link to source directories outside the project.
Tmux builds use exact keys containing source/archive identities, build recipe,
runner image, architecture, compiler and dependency versions. Runtime libraries
are installed before restoring a binary. Reuse checks provenance, binary hash,
ELF architecture and the exact version. A rejected cached artifact is rebuilt.
Only a build that passes its Lisp checks is saved.

Workflow artifacts retain build provenance, logs and the isolated package
evidence. A passing save step alone does not prove that GitHub stored a cache;
a second run of the same revision must restore the exact entry and report
`reused: true` with no configure or make commands. GitHub cache entries are
immutable; rebuilding a rejected exact hit cannot replace that entry.
