# Verification

Run commands from the repository root after `mise install` and `mise run setup`.
Provisioning uses the network; verification does not install dependencies.

`mise run integration` runs transport, core operations, control, decoded
configuration and workspace groups in separate serialized child processes. Each
retains the same 60-second cap and owned-process cleanup checks. ASDF test-op
includes the named integration groups too.

| Command | Tier | Current coverage |
| --- | --- | --- |
| `mise run unit` | Inner | Resource scopes, finite inputs, row/value decoding, graph relations, configuration schema/scope dispatch and defensive ownership |
| `mise run query` | Inner | Scalar/reference agreement, relations, QuerySets, malformed data, limits, ownership and cardinality |
| `mise run regex` | Inner | Optional CL-PPCRE search/full-match semantics, options, ownership and retained causes |
| `mise run json` | Inner | Optional bounded filter documents, allowlists, false/empty/null distinctions and regex opt-in |
| `mise run control` | Inner | Local codecs, byte fidelity, queued/active cancellation, terminal races, CLOS resource identity, live-witness admission, raw notification/reply routing and lexical cleanup; no live connection |
| `tools/lisp.sh tools/test.lisp control-integration` | Outer | Persistent requests/events on 3.8, raw topology/configuration/flow notifications, binary pane output, reply separation, public cancellation, environment preservation, explicit reconnect/recapture without replay, cutover cancellation/cleanup recovery and 3.3a pre-launch rejection |
| `tools/lisp.sh tools/test.lisp configuration-integration` | Outer | Decoded reads on both tmux endpoints, false/absence, sparse keys, inheritance/visibility races, partial evidence, cancellation and truncation |
| `mise run check` | Mid | Source whitespace, all local unit suites, exported docstrings, generated references, excerpts and local documentation links |
| `mise run lint-workflows` | Mid | GitHub Actions syntax, expressions and shell checks |
| `mise run integration` | Outer | Bounded transport, cancellation/cleanup, managed daemon startup/shutdown and failure recovery, linked graphs, attached clients, daemon replacement, named operations, typed configuration reads/mutations, exact target/server termination and tutorial failure cleanup |
| `mise run package` | Outer | Source archive plus isolated core/query/regex/JSON/control consumers and dependency-boundary checks |
| `mise run examples` | Outer | Shipped Lisp recipes, all tutorial Lisp blocks, literal console setup/cleanup, worker consumption signals, optional control streaming and owned daemon cleanup |
| `mise run package-examples` | Outer | Archive-local links, examples, and the installed workspace CLI's validation, preview, apply, reconciliation and stopped-work inspection |
| `mise run docs` | Maintenance | Regenerate API signatures/docstrings, condition hierarchy, applicable models, fields, modules and executable excerpts |

Performance uses a separate tier: `mise run benchmark` compares identical native
reads and measures graph acquisition separately. It is not run by CI or these
test loops. The mid loop includes only the reporter's four critical evidence
checks. See the [benchmark guide](docs/benchmarks.md) for sampling, owned cleanup,
source identity, resource accounting and interpretation limits.

These commands exercise the implemented native core; they do not establish
full-suite compatibility. New operation tests extend the integration suite as
those APIs are implemented. `check` detects generated-document drift without
rewriting files. `docs` deliberately rewrites generated pages and excerpts.
Complete catalog reads exercise many native commands. Each of the named
integration processes retains the same 60-second ceiling; the outer task runs
every group and cleanup checks.
No formatting tool is prescribed for Common Lisp; source checks and SBCL
compilation catch whitespace and reader/compiler errors respectively.
The [testing guide](docs/testing.md) describes FiveAM's interactive workflow and
the exact tmux build cache. Hosted results must identify the tested commit;
local package or integration success does not establish a hosted CI result.

## Recorded local compatibility

The [native matrix record](data/native-compatibility.json) identifies the exact
source revision, native source/binary identities, runtime and per-group results.
On 2026-11-10 UTC, the eleven native integration groups, including owned
workspace application, publication, races and the public API/CLI, passed on all twelve
supported releases: 3.3a, 3.4, 3.5, 3.5a, 3.6, 3.6a, 3.6b, 3.7, 3.7a, 3.7b,
3.7c and 3.8. The native sources and Lisp fixtures at
[07969d0](https://github.com/libtmux/libtmux-lisp/tree/07969d0ab3475cc2f41c060d16897fc00f6fb87c)
are identical at the example-harness correction
[0df49e4](https://github.com/libtmux/libtmux-lisp/tree/0df49e43c1f728e122d907287d55b3f4953024f3).
Each row records its actual revision and executor. Ten intermediate releases
ran in five local two-cell shards, each under 102 seconds including startup.
The [hosted endpoint run](https://github.com/libtmux/libtmux-lisp/actions/runs/42762903411)
passed on 3.3a and 3.8, including extracted examples and cleanup.

Every cell checked owned-process cleanup. Optional control cases are explicitly
skipped below their 3.8 floor; older-daemon refusal is tested. The record retains
each group's actual check, pass and skip counts.

This record covers the implemented native integration surface at its pinned
revision. It does not establish completion of the unfinished suite. CI continues
to test only 3.3a and 3.8; source-archive consumers and complete examples have
separate endpoint evidence. The record's timings are verification costs, not
performance measurements or latency guarantees.

## Source archives and consumers

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
The runner reaps core recipes and the complete owned workspace workflow in
separate children, each capped at 60 seconds. It writes combined passing
evidence only after both current groups pass with matching source and runtime
identities; an earlier invocation cannot supply a missing group.
The installed workspace entry point reads both shipped schemas. Legacy `/1`
checks create the declared topology and report zero mutations on repeat apply.
Owned `/2` checks create recorded physical identities, preview and apply explicit
reconciliation, preserve those identities, and inspect stopped work without
repeating it. The complete native constructor program also verifies shell
output, environment values, retained observations and an unrelated session.
These endpoint checks qualify their recorded inputs; they do not establish
the entire suite's current twelve-release qualification or product completion.
The [tutorial](docs/tutorial.md) explains the recipes and expected values.

Select a tmux binary explicitly when exercising a compatibility cell:

```console
$ LIBTMUX_TEST_TMUX=/path/to/tmux mise run integration
```

Support covers every tmux release from 3.3a through 3.8. CI uses the latest
stable SBCL pin and tests only tmux 3.3a and 3.8 to reduce execution time.
Intermediate releases remain supported; they are not additional CI jobs.

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

Unit tests cover floor rejection without adding a third tmux build to CI.
For an optional maintenance probe, use the exact 3.3 executable:

```console
$ mise exec -- tools/lisp.sh tools/check-floor.lisp /path/to/tmux-3.3/tmux
```

This check asserts the executable's release, expects `unsupported-tmux`, and
checks that opening the client created no daemon socket.

Broader stream/retained-memory qualification, source filtering, shared-site
rendering, broader benchmarks and
integrated acceptance of all required capabilities on both CI endpoints remain
pending. MCP is excluded by policy. The
[capability table](docs/capabilities.md) separates implemented behavior from
those gaps. A passing core package or example does not cover them.
