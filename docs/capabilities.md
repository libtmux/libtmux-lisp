# Capabilities and current limits

Bounded, blocking tmux automation from SBCL on Linux.

- Captured graph traversal, native queries, explicit commands and declarative
  workspace bootstrap.
- Persistent control requests, explicit reconnection and pane-output events
  are optional and need tmux 3.8 or newer.
- Ordinary notifications keep raw bytes. Pane output decodes to octets.
- Larger stream and retained-memory benchmarks remain open.

| Area | Available now | Remaining work |
| --- | --- | --- |
| Runtime | SBCL, ASDF/UIOP, Bash, x86-64 Linux with [pidfd support](transport.md#supported-process-boundary); pins in [.tool-versions](../.tool-versions) | Other implementation/OS support |
| Acquisition | Finite CLOS snapshots, explicit window links, identity, bounds and replacement observations | Complete acceptance after further operations |
| Local processing | Ordinary lists/vectors, functions, owned plists, presence via multiple values, validated relation/regex queries and eager QuerySets | Source-side filter lowering |
| Operations | Creation, rename, selection, geometry, placement, input, buffers, respawn, shell pipes, decoded configuration reads, native printer inspection and typed mutations, captured terminal-client requests, session/server frontend locking, message/command/key printing, key binding/removal, server ACL entries, wait channels (blocking wait/lock require 3.8), explicit entity/server termination and private empty-config daemon scopes | Remaining named server-command helpers |
| Concurrency | Synchronous core calls; one operation per client; optional nonblocking control submission/event waits and explicit generation-changing reconnect | Larger control workloads |
| Streaming/events | Bounded captures and byte buffers; daemon-owned `pipe-pane`; optional raw notifications and native pane-output events with gap/end results and bounded drop-oldest delivery | Long-running streams and retained-memory benchmarks |
| Workspace | Separate bounded JSON/native system; owned logical IDs and records, explicit state/inspection, local drift previews, guarded apply/reconcile and explicit-endpoint CLI; legacy topology reuse | Deletion, process replacement, takeover and replay are outside owned reconciliation |
| Optional integrations | Separate CL-PPCRE regex, bounded query JSON, workspace/CLI and scoped native control connections | Broader mode benchmarks |
| Performance | [Optional native read-path comparison](benchmarks.md) with separate acquisition/startup, launch counts and allocation samples | Large-graph, query and stream workloads; retained heap and broader latency measurements |

## Concurrency

- Public operations block their caller. There is no asyncio or event-loop
  integration.
- Independent clients can run independent operations. Their identity contexts
  differ: never pass one client's observations to another for mutation.
- `pipe-pane` promises no terminal output stream and no lossless event replay.

## Dependencies

- Core needs only portable Common Lisp plus ASDF/UIOP.
- `libtmux/workspace` is a separate ASDF system over core and the locked Jzon
  parser. Its CLI is another separate system.
- Other external libraries stay in the optional systems that need them.

Read next: [public API](api.md), [query API](query-api.md),
[field registry](fields.md) and [tutorial](tutorial.md).

## Supported tmux

- tmux 3.3a through 3.8, including intermediate releases. Plain 3.3 is
  rejected.
- Some flags and operation semantics depend on the live daemon version; see
  [operations](operations.md).
- Decoded configuration reads and mutations accept only reviewed releases in
  that range. An unreviewed neighboring release is rejected, not mapped to
  another version's schema.

Commands and coverage: [verification](../verification.md).

## Before adopting

Check these against your application:

- Platform boundary and required operations.
- Identity policy and the synchronous concurrency model.
- Diagnostics and cleanup behavior.
- For continuous updates, the control system's event coverage and reconnect
  policy.

## Benchmarks

- Report workload, graph size, tmux and toolchain versions, acquisition
  counts, warm and cold timing, distributions and allocations.
- Test-loop timings measure verification cost, not throughput.
