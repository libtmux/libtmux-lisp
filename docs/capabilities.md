# Capabilities and current limits

The implemented systems suit bounded, blocking SBCL/Linux tmux automation with
captured graph traversal, native queries, explicit commands and declarative
workspace bootstrap. Persistent control/events remain future work.

| Area | Available now | Remaining work |
| --- | --- | --- |
| Runtime | SBCL 2.6.10, ASDF/UIOP 3.3.7, Linux x86-64, kernel 6.9+, Bash | Other implementation/OS support |
| Acquisition | Finite CLOS snapshots, explicit window links, identity, bounds and replacement observations | Complete all-version acceptance after further operations |
| Local processing | Ordinary lists/vectors, functions, owned plists, presence via multiple values, validated relation/regex queries and eager QuerySets | Source-side filter lowering |
| Operations | Creation, rename, selection, geometry, placement, input, buffers, respawn, shell pipes, typed option/hook/environment mutations, captured terminal-client requests, session/server frontend locking, message/command/key printing, key binding/removal, server ACL entries, wait channels (blocking wait/lock require 3.8), explicit entity/server termination | Remaining named server-command helpers, decoded configuration readers and daemon bootstrap |
| Concurrency | Synchronous calls; cancellation; one operation per client | Public asynchronous API and persistent control transport |
| Streaming/events | Complete bounded captures and byte buffers; daemon-owned `pipe-pane` | Native event/output subscriptions, bounded delivery, loss and backpressure |
| Workspace | Separate bounded JSON/native system, pure plans, explicit apply, topology reuse and explicit-endpoint CLI | Owned declaration/ID metadata, drift inspection, richer configuration and explicit reconciliation; deletion and process supervision remain outside v1 |
| MCP | Intentionally excluded by project policy | Use a separately maintained external integration if one becomes suitable |
| Optional integrations | Separate CL-PPCRE regex, bounded query JSON and workspace/CLI systems | Control ASDF system |
| Performance | No benchmark claims | Reproducible acquisition/filter/stream workloads and latency/allocation results |

The process backend services stdin/stdout/stderr through nonblocking descriptors
and a private poll loop. Public operations still block their caller. The library
has no Python `asyncio` API or event-loop integration; applying an asyncio
correctness rating to this native Common Lisp core would be misleading.
Independent clients can perform independent operations, but their identity
contexts differ. Do not pass one client's observations to another for mutation.

Portable Common Lisp plus ASDF/UIOP is the default dependency boundary. The
workspace consumer is a separate `libtmux/workspace` ASDF system over core and
the locked Jzon parser; its CLI is another separate system. External libraries
stay isolated in the optional systems that justify them.

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

CI uses the latest stable SBCL pin and checks two tmux releases: the supported
floor, 3.3a, and the newest stable release, currently 3.8. The library rejects
plain 3.3; unit tests check that floor. Runtime flags and some operation
semantics depend on the live daemon version as documented in the
[operation contracts](operations.md).
Configuration mutations require one of the twelve exact reviewed catalogs from
3.3a through 3.8; an unreviewed neighboring release is rejected rather than
silently borrowing another version's schema.

A build-versus-adopt decision should check the platform boundary, required
operations, identity policy, synchronous concurrency model, diagnostics and
cleanup behavior against the actual application. Teams requiring subscriptions,
streaming or an MCP endpoint need a separate integration. The single maintainer
and unreleased status do not change those technical boundaries.

Benchmark evidence must report workload, graph size, tmux/toolchain versions,
acquisition counts, warm/cold timing, distributions and allocations. Test-loop
timings measure verification cost; they are not throughput benchmarks.
