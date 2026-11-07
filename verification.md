# Verification

Run commands from the repository root after `mise install` and `mise run setup`.
Provisioning uses the network; verification does not install dependencies.

| Command | Tier | Current coverage |
| --- | --- | --- |
| `mise run unit` | Inner | Resource scopes, finite inputs, row/value decoding, graph relations and defensive ownership |
| `mise run check` | Mid | Source whitespace, compilation, unit tests, exported docstrings, generated references, excerpts and local documentation links |
| `mise run lint-workflows` | Mid | GitHub Actions syntax, expressions and shell checks |
| `mise run integration` | Outer | Bounded transport, cancellation/cleanup, linked graphs, attached clients, daemon replacement and named operations |
| `mise run package` | Outer | Source archive and isolated core load without optional libraries |
| `mise run examples` | Outer | Shipped Lisp recipes, all tutorial Lisp blocks, literal console setup/cleanup, worker consumption signals and owned daemon cleanup |
| `mise run package-examples` | Outer | Archive-local links and examples executed using the extracted artifact's own scripts |
| `mise run docs` | Maintenance | Regenerate API signatures/docstrings, condition hierarchy, applicable models, fields, modules and executable excerpts |

These commands exercise the implemented native core; they do not establish
full-suite compatibility. New operation tests extend the integration suite as
those APIs are implemented. `check` detects generated-document drift without
rewriting files. `docs` deliberately rewrites generated pages and excerpts.
No formatting tool is prescribed for Common Lisp; source checks and SBCL
compilation catch whitespace and reader/compiler errors respectively.
The [testing guide](docs/testing.md) describes FiveAM's interactive workflow and
the exact tmux build cache. Hosted results must identify the tested commit;
local package or integration success does not establish a hosted CI result.

The package command writes `dist/libtmux-source.tar.gz` and
`dist/package-evidence.json`. The consumer loads the extracted artifact from a
temporary directory with an isolated ASDF source registry and output cache.
It checks that regex, JSON and thread packages were not loaded by core.
The artifact includes its setup pins, tools, guides and executable examples.
`package-examples` checks its local links and runs its own copy of the example
runner with an isolated core registry. `dist/examples-evidence.json` records
the runtime versions, source hashes, tutorial block count and cleanup result.
The [tutorial](docs/tutorial.md) explains the recipes and expected values.

Select a tmux binary explicitly when exercising a compatibility cell:

```console
$ LIBTMUX_TEST_TMUX=/path/to/tmux mise run integration
```

The fixture uses a unique `libtmux-lisp-` temporary directory, an explicit socket
path and `/dev/null` configuration. Child environments omit `TMUX` and
`TMUX_PANE`. A pidfd verifies termination before owned files are removed.
Tests never address the default server.

The integration runner is a dedicated child-process subreaper. It verifies
that no test-owned worker or tmux daemon survives the test image. Production
loading does not change the application's process-reaping policy. Readiness
FIFOs, semaphores and pidfds coordinate tests without polling sleeps.

Verify the unsupported release separately with the exact 3.3 executable:

```console
$ mise exec -- tools/lisp.sh tools/check-floor.lisp /path/to/tmux-3.3/tmux
```

This check asserts the executable's release, expects `unsupported-tmux`, and
checks that opening the client created no daemon socket.

Optional systems, declarative queries, MCP/workspace entry points, shared-site
rendering, benchmarks and the complete full-suite compatibility matrix remain
pending. The [capability table](docs/capabilities.md) separates implemented
behavior from those gaps. A passing core package or example does not cover them.
