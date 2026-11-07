# Contributing

This repository contains a native Common Lisp implementation in development.
Read [AGENTS.md](../AGENTS.md) for change discipline
and [WRITING.md](WRITING.md) for prose and commit conventions.

## Setup

Use Linux x86-64, including WSL, and
[mise 2026.11.3 or newer](https://mise.jdx.dev/getting-started.html).
[.tool-versions](../.tool-versions) owns the SBCL, ASDF and Qlot version pins.
[mise.toml](../mise.toml) reads those pins and supplies the download locations,
checksums, and development tasks. Update each artifact's checksum when its
version changes.

The bootstrap versions were checked on 2026-11-06 against the current stable
[SBCL release](https://www.sbcl.org/),
[ASDF release](https://asdf.common-lisp.dev/), and mise release.
It makes no older-version compatibility commitment. Other host platforms are
not configured yet.

Mise downloads the tools directly from their upstream release sites and
verifies their SHA-256 digests. It exposes SBCL's upstream launcher as `sbcl`.
The tasks load the pinned ASDF source explicitly because SBCL's bundled ASDF
is older. Its postinstall step adds the relative core link needed by Qlot's
child Lisp processes. ASDF is the Lisp build system.

Review the configuration, then trust it:

```console
$ mise trust
```

Install the toolchain outside the verification loops:

```console
$ mise install
```

Install the project-local dependencies from the committed Qlot lock:

```console
$ mise run setup
```

This step uses the network and may compile Qlot's dependencies. Run it outside
test loops. Repeat it after dependency changes; review changes to both
`qlfile` and `qlfile.lock`.

Start a REPL with pinned ASDF, the Qlot environment and local system definition:

```console
$ mise run repl
```

Core loading needs ASDF/UIOP only. FiveAM is a test dependency. CL-PPCRE,
Bordeaux Threads and Jzon are pinned for the separate optional systems.
The runner loads pinned ASDF before `.qlot/setup.lisp` to avoid redundant
ASDF upgrades. It does not install dependencies during a check.

Integration tests require tmux. Set `LIBTMUX_TEST_TMUX` to select a particular
binary; it defaults to `tmux` on PATH. The compatibility floor is 3.3a.

## Verification

Run the timed mid loop from the repository root:

```console
$ /usr/bin/time -p mise run check
```

It checks source whitespace, loads the selected systems and runs the unit
suite. It also checks public docstrings, generated API/field/module references,
example excerpts and local documentation links. Regenerate those pages with
`mise run docs` after a source documentation or registry change.
`mise run examples` executes the shipped recipes and every tutorial Lisp block
on owned tmux servers. `mise run package-examples` repeats that from an isolated
source archive; neither task belongs in the inner or mid loop.
[verification.md](../verification.md) lists the separate integration,
package and installed-consumer checks and their present coverage.
Use the [FiveAM testing guide](../docs/testing.md) for focused REPL work,
redefinition, reruns and debugger entry. Workflow changes also require
`mise run lint-workflows`, using pinned actionlint.

Keep future checks within these whole-command budgets, including setup and
startup:

| Loop | Budget | Target | Scope |
| --- | --- | --- | --- |
| Inner | Under 5 seconds | Under 2 seconds | Critical behavior affected by the edit |
| Mid | Under 30 seconds | Under 10 seconds | Unit suites, lint, generated-file checks |
| Outer | Under 5 minutes | Under 60 seconds | Builds, packages, docs, integration, matrices |

Run the inner loop after edits, the mid loop before handoff, and the outer
loop before a commit or pull request. Keep acquisition and live tmux tests in
the integration tier; local domain and query tests must not contact tmux.

Keep network access, installs, production builds, browser launches, sleeps,
and broad corpus scans out of inner and mid loops. Investigate any timeout
or wait over one second; use events or subscriptions instead of sleeps.
Tag slow tests with a one-line reason and put them in the outer loop. Fix an
over-budget loop before adding tests. Add tests only for critical behavior.

Benchmarks are separate: keep each run under ten minutes and a full sweep
under one hour. Reduce workloads instead of raising the limits.

## Tmux fixtures

Each test or probe must own a unique `libtmux-lisp-` socket and temporary
directory. Address the socket explicitly, clear inherited `TMUX` and
`TMUX_PANE`, and clean up only resources created by that run. Never use or
kill the default server. Record the exact tmux version and verify cleanup.

## Pull requests

Keep one logical topic per commit. Preserve unrelated work and stage explicit
paths. Describe the resulting behavior, why it matters, commands run, elapsed
times, and evidence gaps. An empty system loading successfully does not prove
an implemented library. The project uses MIT.
