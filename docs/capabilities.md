# Capability reports and current limits

Use [`libtmux:capabilities`](api.md#capabilities-function) to observe the selected
daemon, then [`capability`](api.md#capability-function) to inspect a requirement
or [`supports-p`](api.md#supports-p-function) to choose a native path. Run the
[complete example](../examples/capabilities.lisp):

```console
$ mise exec -- sbcl --script examples/capabilities.lisp
```

The report contains the observed release, daemon provenance and feature plists.
Each feature names its minimum release, affected APIs, native commands,
support decision and handling. `:escaped-format` and `:raw-paste` identify
existing fallbacks; `:reject` means the operation signals
[`unsupported-capability`](api.md#unsupported-capability-type).
An unknown feature signals [`invalid-argument`](api.md#invalid-argument-type).
The generated [capability manifest](../capabilities.json) uses the same registry.

Readers return owned copies without I/O. Reports remain historical after
cleanup or daemon replacement; they do not renew captured targets, grant
permission or bypass exact option, field and workspace schema checks.
Discovery uses the daemon's live reply, not the cached executable release from
[`tmux-version`](api.md#tmux-version-function).

Core discovery blocks under the client's existing operation lease. Its timeout,
cancellation token and output limit bound native work. It starts no daemon and
invokes no after-hooks. Two temporary witnesses must agree within the same
deadline and combined byte budget. This observes an acquisition interval; it
does not reserve the endpoint or keep a returned report live.

Keep tmux's native `list-commands` spelling unaliased,
including while discovery runs: an administrator who replaces that bootstrap
command can execute arbitrary server code. Discovery does not audit aliases
with `show-options`, because that command can itself invoke an after-hook.

The optional control system offers
[`submit-capabilities`](control-api.md#submit-capabilities-function) and
[`await-capabilities`](control-api.md#await-capabilities-function). Submission
returns a request promptly; retrieval returns three values: report, delivery
and raw request result. A completed observation yields the report and `:ready`.
A wait timeout yields `nil`, `:timeout`, `nil` and does not cancel the request.
A terminal request failure yields `nil`, `:ready` and its failure result.
Malformed or mismatched successful replies signal the existing decode or
continuity condition; they never produce a report from cached peer data.

Use [`cancel-request`](control-api.md#cancel-request-function) for explicit
cancellation. Cancelling queued work removes it; cancelling active work closes
the connection. Closing a connection settles its requests. Discovery stays on
the original peer even if its socket path moves or its parent core client
closes. It never rebinds to a replacement daemon. See
[control ownership and bounds](control.md#submission-completion-and-cancellation).

## Current surface

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

- Core operations block their caller. Optional control submission uses its
  existing worker; waiting for a result blocks only the waiting caller.
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
