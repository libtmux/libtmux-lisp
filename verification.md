# Verification

Run commands from the repository root after `mise install` and `mise run setup`.
Provisioning uses the network; verification does not install dependencies.

| Command | Tier | Current coverage |
| --- | --- | --- |
| `mise run unit` | Inner | Resource scopes, finite inputs, row decoding, graph relations and defensive ownership |
| `mise run check` | Mid | Source whitespace, compilation and unit tests |
| `mise run lint-workflows` | Mid | GitHub Actions syntax, expressions and shell checks |
| `mise run integration` | Outer | Bounded transport, cancellation/cleanup, linked graphs, attached clients and daemon replacement |
| `mise run package` | Outer | Source archive and isolated core load without optional libraries |

The transport and capture checkpoints do not establish full engine compatibility.
The captured-graph checkpoint had 80 unit checks and 167 integration checks.
Operation and creation checks extend that suite as those APIs are implemented.
No formatting tool is prescribed for Common Lisp; source checks and SBCL
compilation catch whitespace and reader/compiler errors respectively.
The [testing guide](docs/testing.md) describes FiveAM's interactive workflow and
the exact tmux build cache. Hosted results must identify the tested commit;
local package or integration success does not establish a hosted CI result.

The package command writes `dist/libtmux-source.tar.gz` and
`dist/package-evidence.json`. The consumer loads the extracted artifact from a
temporary directory with an isolated ASDF source registry and output cache.
It checks that regex, JSON and thread packages were not loaded by core.

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

Executable examples, generated references, optional systems, MCP/workspace
entry points, shared-site rendering and the complete compatibility suite remain
unverified until their implementation tasks land. Add their exact commands here
when those commands exist; a passing package load does not cover them.
