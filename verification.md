# Verification

Run commands from the repository root after `mise install` and `mise run setup`.
Provisioning uses the network; verification does not install dependencies.

| Command | Tier | Current coverage |
| --- | --- | --- |
| `mise run unit` | Inner | Resource scopes, finite inputs, row/value decoding, graph relations, configuration schema/scope dispatch and defensive ownership |
| `mise run query` | Inner | Scalar/reference agreement, relations, QuerySets, malformed data, limits, ownership and cardinality |
| `mise run regex` | Inner | Optional CL-PPCRE search/full-match semantics, options, ownership and retained causes |
| `mise run json` | Inner | Optional bounded filter documents, allowlists, false/empty/null distinctions and regex opt-in |
| `mise run check` | Mid | Source whitespace, all local unit suites, exported docstrings, generated references, excerpts and local documentation links |
| `mise run lint-workflows` | Mid | GitHub Actions syntax, expressions and shell checks |
| `mise run integration` | Outer | Bounded transport, cancellation/cleanup, linked graphs, attached clients, daemon replacement, named operations, typed configuration mutations, exact target/server termination and tutorial failure cleanup |
| `mise run package` | Outer | Source archive plus isolated core/query/regex/JSON consumers and dependency-boundary checks |
| `mise run examples` | Outer | Shipped Lisp recipes, all tutorial Lisp blocks, literal console setup/cleanup, worker consumption signals and owned daemon cleanup |
| `mise run package-examples` | Outer | Archive-local links, examples, and the installed workspace CLI's validate/plan/apply/reapply workflow |
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
It checks that query, regex, JSON and thread packages were not loaded by core,
then loads `libtmux/query` separately without pulling those optional libraries.
Separate consumers load and exercise `libtmux/regex` and `libtmux/json` through
the same locked dependency setup.
The artifact includes its setup pins, tools, guides and executable examples.
`package-examples` checks its local links and runs its own copy of the example
runner with an isolated core registry. `dist/examples-evidence.json` records
the runtime versions, source hashes, tutorial block count and cleanup result.
The installed workspace entry point reads the shipped JSON file, creates its
declared live topology, and reports zero retained mutations on repeat apply.
These checks qualify the implemented v1 behavior; full ownership metadata,
drift inspection and explicit reconciliation remain separate unfinished work.
The [tutorial](docs/tutorial.md) explains the recipes and expected values.

Select a tmux binary explicitly when exercising a compatibility cell:

```console
$ LIBTMUX_TEST_TMUX=/path/to/tmux mise run integration
```

The fixture uses a unique `libtmux-lisp-` temporary directory, an explicit socket
path and `/dev/null` configuration. Child environments omit `TMUX` and
`TMUX_PANE`. A pidfd verifies termination before owned files are removed.
Tests never address the default server. Attached-client tests launch ordinary
PTY clients through SBCL's fork path, without control mode. They join captured
PIDs to retained child pidfds, observe native SIGTSTP stops, and use an owned
bounded FIFO lock command. Request acknowledgements and frontend effects have
separate assertions. Partial acquisition and nonlocal exits check cleanup.
Session/server locking uses two ordinary frontends in separate sessions. Native
suspended flags establish recipient scope, and independent FIFO readiness proves
each requested lock program started before owned cleanup releases it.
Wait-channel tests prove a waiter is queued through native listing before
cancellation, then inspect the daemon's remaining queue. Lost lock
acknowledgements remain separate from queued-waiter disposal; neither closing
nor cancellation automatically releases a granted lock.
Message-printing tests distinguish literal and explicit format input, physical
and link context, foreign authority, versioned intermediate limits and
after-hook text in the ordinary printer stream.
Key-binding tests send bytes through an owned ordinary PTY frontend. Native
hook/channel acknowledgements prove stored command execution and order a
second key after removal. Direct fixture reads verify literal values and
parse-time environment effects retained after a failed binding.
Printer profiles distinguish tmux 3.7 through 3.7c's single-row status routing
and missing-key success from normal multi-row output and other releases.
Server-access fixtures use the existing `nobody` account and its primary group
on private sockets, without changing OS identities or permissions. They prove
entry lifecycle, literal names, group gating and tmux 3.8's recomputation of an
unrelated owner's frontend flags. Cross-user authorization, connection and
revocation remain unverified.

The integration runner is a dedicated child-process subreaper. It verifies
that no test-owned worker or tmux daemon survives the test image, including an
injected tutorial failure before its Lisp termination call. Production loading
does not change the application's process-reaping policy. Readiness FIFOs,
semaphores and pidfds coordinate tests without polling sleeps.

Verify the unsupported release separately with the exact 3.3 executable:

```console
$ mise exec -- tools/lisp.sh tools/check-floor.lisp /path/to/tmux-3.3/tmux
```

This check asserts the executable's release, expects `unsupported-tmux`, and
checks that opening the client created no daemon socket.

Control/events, source filtering, shared-site rendering, benchmarks and the
complete full-suite compatibility matrix remain pending. MCP is excluded by
policy. The
[capability table](docs/capabilities.md) separates implemented behavior from
those gaps. A passing core package or example does not cover them.
