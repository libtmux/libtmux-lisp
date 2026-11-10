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
The Lisp toolchain tracks current stable releases. Tmux compatibility covers
3.3a through 3.8, including intermediate releases. Other host platforms are
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

Core and native-query loading need ASDF/UIOP only. FiveAM is a test dependency.
CL-PPCRE, Bordeaux Threads and Jzon are pinned for the separate optional
systems that justify them. MCP is intentionally outside this port's scope.
The runner loads pinned ASDF before `.qlot/setup.lisp` to avoid redundant
ASDF upgrades. It does not install dependencies during a check.

Integration tests require tmux. Set `LIBTMUX_TEST_TMUX` to select a particular
binary; it defaults to `tmux` on PATH. The supported range is 3.3a through 3.8.
CI tests only those two endpoints to reduce build time.

## Verification

Run the timed mid loop from the repository root:

```console
$ /usr/bin/time -p mise run check
```

It checks source whitespace, loads the selected systems and runs the core,
native-query, regex, JSON and workspace suites. It also checks public
docstrings, generated API/field/operator/module references,
the generated configuration catalog, example excerpts and local documentation
links. Regenerate those pages with
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

Incomplete-workspace read and race scenarios run in the separate
`workspace-inspection-integration` group. The integration and archive tasks run
it with the same 60-second child cap as the other live groups.
Writer contention, immutable metadata and interrupted-progress scenarios run in
the separate `workspace-writer-integration` group under that same cap.
Complete owned application, publication failures and live dispatch races run in
`workspace-apply-integration`, `workspace-publication-integration` and
`workspace-apply-race-integration`. Both native and extracted-archive tasks run
each group as a separate child; the 60-second cap applies to each group.

Keep network access, installs, production builds, browser launches, sleeps,
and broad corpus scans out of inner and mid loops. Investigate any timeout
or wait over one second; use events or subscriptions instead of sleeps.
Tag slow tests with a one-line reason and put them in the outer loop. Fix an
over-budget loop before adding tests. Add tests only for critical behavior.

Benchmarks are separate: keep each run under ten minutes and a full sweep
under one hour. Reduce workloads instead of raising the limits.

Run the native-query suite alone while working on local filtering:

```console
$ mise run query
```

Run either optional query integration independently:

```console
$ mise run regex
```

```console
$ mise run json
```

## Configuration source catalogs

The core loads committed native Lisp data. It needs no JSON library or C
compiler at runtime. `data/options-catalog.json` records exact-version source
facts; `src/options-catalog.lisp` is generated from them. No runtime option
defaults are inferred from C initializers. `mise run check` verifies provenance
markers and generated-file freshness without fetching or compiling tmux.

Regenerate the native file after a reviewed fact change:

```console
$ mise run catalogs
```

To refresh the facts, set `TMUX_SOURCE` to a local tmux Git checkout containing
the commits in `tools/tmux-sources.json`. The maintenance extractor reads Git
objects, preprocesses each table and compares the result with a compiled C
schema. It requires `cc` and the documented Linux x86-64 integer profile. It
does not alter that tmux checkout or install anything. Run it outside inner
and mid loops:

```console
$ python3 tools/extract-options-catalog.py \
    --repo . \
    --tmux-source "$TMUX_SOURCE"
```

The output and source-verification evidence go under `build/options-catalog/`.
Review them, then import the verified catalog and regenerate the native file:

```console
$ python3 tools/options-catalog.py import \
    --source-catalog build/options-catalog/catalog.json
```

An unknown source construct, changed source pin or unsupported schema must
fail for review. A neighboring version's catalog is not a fallback.

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

The documentation workflow builds artifacts for pushes, pull requests and tags.
Publishing requires a manual dispatch with `publish` enabled. Keep both shared
workflow pins at the same reviewed commit. A passing build is not publication.
