# Capabilities and current limits

The implemented systems suit bounded, blocking SBCL/Linux tmux automation with
captured graph traversal, native queries, explicit commands and declarative
workspace bootstrap. Persistent control requests, explicit reconnection and pane-output events are
optional on tmux 3.8+. Ordinary notifications retain raw bytes; pane output
is decoded to octets. Larger stream and retained-memory benchmarks remain open.

| Area | Available now | Remaining work |
| --- | --- | --- |
| Runtime | SBCL 2.6.10, ASDF/UIOP 3.3.7, Linux x86-64, kernel 6.9+, Bash | Other implementation/OS support |
| Acquisition | Finite CLOS snapshots, explicit window links, identity, bounds and replacement observations | Complete acceptance after further operations |
| Local processing | Ordinary lists/vectors, functions, owned plists, presence via multiple values, validated relation/regex queries and eager QuerySets | Source-side filter lowering |
| Operations | Creation, rename, selection, geometry, placement, input, buffers, respawn, shell pipes, decoded configuration reads, native printer inspection and typed mutations, captured terminal-client requests, session/server frontend locking, message/command/key printing, key binding/removal, server ACL entries, wait channels (blocking wait/lock require 3.8), explicit entity/server termination and private empty-config daemon scopes | Remaining named server-command helpers |
| Concurrency | Synchronous core calls; one operation per client; optional nonblocking control submission/event waits and explicit generation-changing reconnect | Larger control workloads |
| Streaming/events | Bounded captures and byte buffers; daemon-owned `pipe-pane`; optional raw notifications and native pane-output events with gap/end results and bounded drop-oldest delivery | Long-running streams and retained-memory benchmarks |
| Workspace | Separate bounded JSON/native system, pure plans, explicit apply, topology reuse and explicit-endpoint CLI | Owned declaration/ID metadata, drift inspection, richer configuration and explicit reconciliation; deletion and process supervision remain outside v1 |
| MCP | Intentionally excluded by project policy | Use a separately maintained external integration if one becomes suitable |
| Optional integrations | Separate CL-PPCRE regex, bounded query JSON, workspace/CLI and scoped native control connections | Broader mode benchmarks |
| Performance | [Optional native read-path comparison](benchmarks.md) with separate acquisition/startup, launch counts and allocation samples | Large-graph, query and stream workloads; retained heap and broader latency qualification |

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

The supported tmux range is 3.3a through 3.8, including intermediate releases.
CI uses the latest stable SBCL pin and checks only the two endpoints, 3.3a and
3.8, to reduce build time. The library rejects plain 3.3; unit tests check that
floor. Runtime flags and some operation semantics depend on the live daemon
version as documented in the
[operation contracts](operations.md).
Decoded configuration reads and mutations require one of the twelve exact reviewed catalogs from
3.3a through 3.8; an unreviewed neighboring release is rejected rather than
silently borrowing another version's schema.

A build-versus-adopt decision should check the platform boundary, required
operations, identity policy, synchronous concurrency model, diagnostics and
cleanup behavior against the actual application. Teams requiring continuous updates should check the optional control system
against their required event coverage and reconnect policy. MCP stays excluded. The single maintainer
and unreleased status do not change those technical boundaries.

Benchmark evidence must report workload, graph size, tmux/toolchain versions,
acquisition counts, warm/cold timing, distributions and allocations. Test-loop
timings measure verification cost; they are not throughput benchmarks.
