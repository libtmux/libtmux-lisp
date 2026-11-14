# Testing

Run local tests in FiveAM at the REPL. Run live tmux tests through the
separate command, so the process owner can check fixture cleanup.

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
rerun the second and third previous selections without shifting the history.
To enter the debugger on an unexpected condition, use `debug!`:

```lisp
(fiveam:debug! 'libtmux.tests::record-codec-preserves-text-and-presence)
```

FiveAM supplies `retest` and `ignore` restarts while the condition is active.
After a focused change, run the complete unit suite:

```lisp
(fiveam:run! 'libtmux.tests::unit)
```

Run the native-query suite without contacting tmux:

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

FiveAM compiles test bodies at definition time by default.

- After changing a macro a test uses, re-evaluate that test definition too.
- To study macro redefinition, `def-test` accepts `:compile-at :run-time`.
- Upstream's homepage describes older behavior. See the pinned
  [test definitions](https://github.com/lispci/fiveam/blob/3ba1300a9dd6bafdaef2af76d261d73bdf7e4bf0/src/test.lisp)
  and [runner](https://github.com/lispci/fiveam/blob/3ba1300a9dd6bafdaef2af76d261d73bdf7e4bf0/src/run.lisp).

`run!` returns a Boolean.

- Scripts must check it to return a failing process status.
- Unknown names and entirely skipped selections can report no failures. Select
  a known test or suite and read the check and skip counts.
- The shipped runner selects declared suites and checks the result before
  exiting.

The mid loop runs the five local suites in one image.

- Each system loads just before its suite, so core and query tests run before
  optional libraries load.
- A failure stops the remaining suites.
- Package-consumer checks still use isolated images to verify loading
  boundaries.
- Live CLI apply/reapply runs through the extracted package's entry point in
  `mise run package-examples`. Core workspace behavior stays in integration.

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

This outer loop uses a dedicated process owner and subreaper.

- No test-owned child or daemon may survive the Lisp image.
- Tests wait on application signals. A send acknowledgment alone does not show
  the application consumed the input.
- Loop budgets and coverage: [verification](../verification.md).

## GitHub Actions

CI runs the same mise tasks and FiveAM suites as local development, with the
toolchain in [.tool-versions](../.tool-versions) and the Qlot lock.

- Pushes to `master`, pull requests and manual runs check tmux 3.3a and 3.8,
  the two ends of the supported range. Intermediate releases are supported but
  not built in CI.
- Unit tests cover rejection of plain 3.3 without another tmux build.
- The runner image must meet the
  [process requirements](transport.md#supported-process-boundary).

Run the same endpoint checks manually:

```console
$ gh workflow run tests.yml \
    --ref master
```

Caches:

- Qlot dependencies: keyed by toolchain configuration and lock. The cache holds
  both `.qlot` and Qlot's shared cache, because installed systems link to
  sources outside the project.
- tmux builds: exact keys from source/archive identities, build recipe, runner
  image, architecture, compiler and dependency versions. Runtime libraries are
  installed before a binary is restored.
- Reuse checks provenance, binary hash, ELF architecture and the exact version.
  A rejected cached artifact is rebuilt.
- Only a build that passes its Lisp checks is saved.
- GitHub cache entries are immutable. Rebuilding a rejected exact hit cannot
  replace that entry.
- A passing save step does not prove GitHub stored the cache. A second run of
  the same revision must restore the exact entry and report `reused: true`
  with no configure or make commands.
- Workflow artifacts keep build provenance, logs and the isolated package
  evidence.
