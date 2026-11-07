# Capabilities and current limits

The implemented core suits bounded, blocking SBCL/Linux tmux automation with
captured graph traversal and explicit commands. It is not yet the complete
query, control/events, agent and workspace suite described by the project goal.

| Area | Available now | Remaining work |
| --- | --- | --- |
| Runtime | SBCL 2.6.10, ASDF/UIOP 3.3.7, Linux x86-64, kernel 6.9+, Bash | Other implementation/OS support |
| Acquisition | Finite CLOS snapshots, explicit window links, identity, bounds and replacement observations | Complete all-version acceptance after further operations |
| Local processing | Ordinary lists/vectors, functions, owned plists, presence via multiple values | Declarative compiler and optional query-set |
| Operations | Creation, rename, selection, geometry, placement, input, buffers, respawn, shell pipes | Options/hooks/environment, lifecycle/bootstrap and attached-client operations |
| Concurrency | Synchronous calls; cancellation; one operation per client | Public asynchronous API and persistent control transport |
| Streaming/events | Complete bounded captures and byte buffers; daemon-owned `pipe-pane` | Native event/output subscriptions, bounded delivery, loss and backpressure |
| MCP/workspaces | No implemented module or executable | Protocols, discoverable tools, authority policy and external consumer tests |
| Optional integrations | Dependency pins reserved | Regex, JSON and control ASDF systems |
| Performance | No benchmark claims | Reproducible acquisition/filter/stream workloads and latency/allocation results |

The process backend services stdin/stdout/stderr through nonblocking descriptors
and a private poll loop. Public operations still block their caller. The library
has no Python `asyncio` API or event-loop integration; applying an asyncio
correctness rating to this native Common Lisp core would be misleading.
Independent clients can perform independent operations, but their identity
contexts differ. Do not pass one client's observations to another for mutation.

No MCP setup command exists yet. An agent can read the [public API](api.md),
[field registry](fields.md) and [tutorial](tutorial.md), but these documents are
not an MCP server. No terminal output stream or lossless event-replay guarantee
is implied by `pipe-pane`.

## Evidence and adoption

`mise run examples` executes the shipped Lisp examples on an owned socket with
empty tmux configuration. `mise run check` checks unit semantics, exported
docstrings, generated API/field/module pages, executable excerpts and local
documentation links. `mise run package` checks an isolated ASDF consumer;
`mise run integration` exercises the native transport and named operations.
See [verification](../verification.md) for evidence boundaries and commands.

Every-push CI checks exact tmux 3.3a and 3.8. A twelve-version workflow exists;
its configuration alone is not proof that all cells pass. The library rejects
plain 3.3. Runtime flags and some operation semantics depend on the live daemon
version as documented in the [operation contracts](operations.md).

A build-versus-adopt decision should check the platform boundary, required
operations, identity policy, synchronous concurrency model, diagnostics and
cleanup behavior against the actual application. Teams requiring native MCP,
subscriptions or streaming must account for that unfinished implementation.
The single maintainer and unreleased status do not change those technical gaps.

Benchmark evidence must report workload, graph size, tmux/toolchain versions,
acquisition counts, warm/cold timing, distributions and allocations. Test-loop
timings measure verification cost; they are not throughput benchmarks.
