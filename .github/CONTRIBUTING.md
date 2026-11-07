# Contributing

This repository contains a scaffold. Its ASDF system has no source components
or implementation tests. Read [AGENTS.md](../AGENTS.md) for change discipline
and [WRITING.md](WRITING.md) for prose and commit conventions.

## Setup

Use Linux x86-64, including WSL, and
[mise 2026.11.3 or newer](https://mise.jdx.dev/getting-started.html).
[.tool-versions](../.tool-versions) owns the SBCL and ASDF version pins.
[mise.toml](../mise.toml) reads those pins and supplies the download locations,
checksums, and development tasks. Update each artifact's checksum when its
version changes.

The bootstrap versions were checked on 2026-11-06 against the current stable
[SBCL release](https://www.sbcl.org/),
[ASDF release](https://asdf.common-lisp.dev/), and mise release.
It makes no older-version compatibility commitment. Other host platforms are
not configured yet.

Mise downloads SBCL and ASDF directly from their upstream release sites and
verifies their SHA-256 digests. It exposes SBCL's upstream launcher as `sbcl`.
The tasks load the pinned ASDF source explicitly because SBCL's bundled ASDF
is older. ASDF is the Lisp build system, not the asdf-vm version manager.

Review the configuration, then trust it:

```console
$ mise trust
```

Install the toolchain outside the verification loops:

```console
$ mise install http:sbcl http:asdf-lisp
```

Start a REPL with the pinned ASDF version and local system definition:

```console
$ mise run repl
```

No external Lisp libraries are needed for the scaffold. Select a dependency
manager when implementation introduces dependencies.

The metadata check does not require tmux. Install
[tmux 3.8 or newer](https://github.com/tmux/tmux/releases/tag/3.8) before future
runtime work. Mise's default tmux binary feed does not yet provide 3.8.

## Verification

Run the timed metadata check from the repository root:

```console
$ /usr/bin/time -p mise run check
```

It loads `libtmux.asd` and the empty `libtmux` system, then prints the package,
SBCL, and ASDF versions. This is a syntax and loading check, not a functional
test. There is no implementation, packaging pipeline, or compatibility matrix
to qualify yet.

Keep future checks within these whole-command budgets, including setup and
startup:

| Loop | Budget | Target | Scope |
| --- | --- | --- | --- |
| Inner | Under 5 seconds | Under 2 seconds | Critical behavior affected by the edit |
| Mid | Under 30 seconds | Under 10 seconds | Unit suites, lint, generated-file checks |
| Outer | Under 5 minutes | Under 60 seconds | Builds, packages, docs, integration, matrices |

Run the inner loop after edits, the mid loop before handoff, and the outer
loop before a commit or pull request. During bootstrap, the metadata check
is the available inner check; also inspect instruction links, tool metadata,
ignore rules, and the final file list before handoff.

Keep network access, installs, production builds, browser launches, sleeps,
and broad corpus scans out of inner and mid loops. Investigate any timeout
or wait over one second; use events or subscriptions instead of sleeps.
Tag slow tests with a one-line reason and put them in the outer loop. Fix an
over-budget loop before adding tests. Add tests only for critical behavior.

Benchmarks are separate: keep each run under ten minutes and a full sweep
under one hour. Reduce workloads instead of raising the limits.

## Future tmux checks

Each test or probe must own a unique `libtmux-lisp-` socket and temporary
directory. Address the socket explicitly, clear inherited `TMUX` and
`TMUX_PANE`, and clean up only resources created by that run. Never use or
kill the default server. Record the exact tmux version and verify cleanup.

## Pull requests

Keep one logical topic per commit. Preserve unrelated work and stage explicit
paths. Describe the resulting behavior, why it matters, commands run, elapsed
times, and evidence gaps. An empty system loading successfully does not prove
an implemented library. Settle the project license before publication.
