# Capabilities and current limits

The implemented core suits bounded, blocking SBCL/Linux tmux automation with
captured graph traversal, native queries and explicit commands. It is not yet
the complete control/events and workspace suite described by the project goal.

| Area | Available now | Remaining work |
| --- | --- | --- |
| Runtime | SBCL 2.6.10, ASDF/UIOP 3.3.7, Linux x86-64, kernel 6.9+, Bash | Other implementation/OS support |
| Acquisition | Finite CLOS snapshots, explicit window links, identity, bounds and replacement observations | Complete all-version acceptance after further operations |
| Local processing | Ordinary lists/vectors, functions, owned plists, presence via multiple values, validated relation queries and eager QuerySets | Regex and source-side filter lowering |
| Operations | Creation, rename, selection, geometry, placement, input, buffers, respawn, shell pipes | Options/hooks/environment, lifecycle/bootstrap and attached-client operations |
| Concurrency | Synchronous calls; cancellation; one operation per client | Public asynchronous API and persistent control transport |
| Streaming/events | Complete bounded captures and byte buffers; daemon-owned `pipe-pane` | Native event/output subscriptions, bounded delivery, loss and backpressure |
| Workspace | No implemented module or executable | Separate ASDF system, installed loader/CLI and owned-fixture consumer tests |
| MCP | Intentionally excluded by project policy | Use a separately maintained external integration if one becomes suitable |
| Optional integrations | Native query system is separate and dependency-free | Regex, JSON and control ASDF systems |
| Performance | No benchmark claims | Reproducible acquisition/filter/stream workloads and latency/allocation results |

The process backend services stdin/stdout/stderr through nonblocking descriptors
and a private poll loop. Public operations still block their caller. The library
has no Python `asyncio` API or event-loop integration; applying an asyncio
correctness rating to this native Common Lisp core would be misleading.
Independent clients can perform independent operations, but their identity
contexts differ. Do not pass one client's observations to another for mutation.

Portable Common Lisp plus ASDF/UIOP is the default dependency boundary. The
required workspace consumer will be a separate `libtmux/workspace` ASDF system
that depends on `libtmux` and only the sibling systems its loader and CLI need.
External libraries stay isolated in the optional systems that justify them.

MCP is intentionally outside this port's product scope; it is not an unfinished
package or release gate. An agent can still read the [public API](api.md),
[query API](query-api.md), [field registry](fields.md) and [tutorial](tutorial.md),
but these documents are not a protocol server. No terminal output stream or
lossless event-replay guarantee is implied by `pipe-pane`.

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
cleanup behavior against the actual application. Teams requiring subscriptions,
streaming or an MCP endpoint need a separate integration. The single maintainer
and unreleased status do not change those technical boundaries.

Benchmark evidence must report workload, graph size, tmux/toolchain versions,
acquisition counts, warm/cold timing, distributions and allocations. Test-loop
timings measure verification cost; they are not throughput benchmarks.
