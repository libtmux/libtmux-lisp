# ADR 0001: Native Common Lisp engine and captured query model

## Abstract

libtmux-lisp owns its tmux integration in Common Lisp. It acquires finite
captured objects, exposes local sequence processing, and performs external
operations through an explicit client. The first process backend targets SBCL
on Linux. Queries compile validated data into native predicates; optional ASDF
systems add regex, interchange and workspace automation.

This record explains those choices, their costs and the conditions that would
justify changing them. Start with the [tutorial](../tutorial.md) for executable
usage and the [capability table](../capabilities.md) for current availability.

## Status

Proposed for architectural acceptance after review. Implementation status and
release qualification are separate: a committed implementation does not settle
an architectural review, and acceptance does not establish runtime support.
The decisions below describe the committed core and the boundaries of remaining
work. They preserve the existing ownership and explicit-effect contracts.

Core acquisition, local queries, optional codecs, named mutations and workspace
creation are implemented. Decoded configuration readers, source filtering,
persistent control/events and final suite qualification remain open. Private
decoder or relay experiments do not establish a public acquisition backend.
The [verification record](../../verification.md) owns commands and evidence;
this ADR owns the architectural decisions.

## Context and problem

tmux presents commands, formats, contextual listings and a control protocol.
A useful Lisp library must turn these into objects and functions while keeping
observation, targeting, process ownership and uncertain command outcomes clear.

The Python library provides a useful behavioral reference. Its
[design rationale at v0.62.0](https://github.com/tmux-python/libtmux/blob/v0.62.0/docs/topics/design-decisions.md#why-orm-style-objects)
explains ORM-style objects; its
[`Pane.refresh`](https://github.com/tmux-python/libtmux/blob/v0.62.0/src/libtmux/pane.py#L134-L164)
updates an existing pane object. Lisp callers should instead be able to retain
one observation, inspect it after closing the client, and combine ordinary
sequence functions without triggering new tmux commands.

The OCaml port offers another relevant comparison: its pure core separates
[`Source`](https://github.com/libtmux/libtmux-ocaml/blob/53a51bed2caa198be0fc3d81cb464e29d9f29403/lib/libtmux.mli#L92-L108),
[`Window_link`](https://github.com/libtmux/libtmux-ocaml/blob/53a51bed2caa198be0fc3d81cb464e29d9f29403/lib/libtmux.mli#L258-L283)
and [`Expr`](https://github.com/libtmux/libtmux-ocaml/blob/53a51bed2caa198be0fc3d81cb464e29d9f29403/lib/libtmux.mli#L552-L638).
These are behavioral precedents. Common Lisp owns its representation,
conditions, multiple-value contracts and resource scopes.

## Scope and non-goals

This decision covers the library's system boundaries, captured model, identity,
query execution, subprocess lifecycle, command outcomes and extension policy.
Portable domain and query code is the design aim; supported runtime claims
cover only tested implementations and operating systems.

The selected implementation is native Common Lisp. Java, ABCL and a JVM
sidecar are outside its architecture. MCP is excluded by project policy. The
library does not implement a tmux daemon, a terminal emulator or operating-system
confinement. Public asynchronous operations and event subscriptions remain
separate unfinished capabilities.

## Terminology

- **Acquisition** is external work that reads tmux over a recorded interval.
- **Capture** is that acquisition's retained data; a **snapshot** is its graph.
  An **observation** is one captured entity or graph, not live state.
- **Context** identifies one library client. **Generation** identifies its
  trusted daemon continuity interval. A **witness** is the process/socket
  evidence used to check that continuity.
- A **guard** checks supported server/target facts before dispatch. A
  **receipt** is command-specific output used to attribute execution. Neither
  implies rollback or a transaction over all captured fields.

## Architectural decisions

### Own the engine and isolate implementation-specific process code

The `libtmux` ASDF system owns decoding, CLOS observations, identity, command
encoding, dispatch and typed conditions. Its portable loading dependency is
ASDF/UIOP. SBCL-specific modules contain descriptors, process supervision,
synchronization and Linux process identity. The
[source module map](../modules.md) identifies those responsibilities.

ASDF/UIOP and the supported backend are consumer requirements. Mise reproduces
the contributor toolchain; Qlot locks development and optional dependencies.
An existing ASDF application does not need either tool merely to load the core.
ASDF here is the Common Lisp build system.

The first backend requires SBCL on Linux x86-64, pidfds, eventfd, Bash and the
required libc wrappers. Its process-group pidfd flag requires the upstream
[Linux 6.9 facility](https://github.com/torvalds/linux/blob/v6.9/include/uapi/linux/pidfd.h#L13-L16).
Kernel, libc and executable requirements are separate; a distribution or WSL
label does not establish them. Script shims are rejected by the native ELF
executable policy. Supply the underlying binary explicitly.

[`open-client`](../api.md#open-client) rejects an unsupported runtime profile
before resolving the executable. ASDF selects the native backend files only
for SBCL/Linux x86-64. The first open probes pidfd/group signalling, eventfd and
the Bash launcher; [`unsupported-platform`](../api.md#unsupported-platform)
retains a requirement identifier and any underlying probe condition. The
checks are cached within the image and do not establish continuing availability
or broader platform qualification. Non-SBCL hosts have no replacement backend.
Calls use libc bindings through `sb-alien`; adding CFFI alone would not qualify
ARM64 or replace Linux witness semantics. Other platforms need their own
verified profile or backend.

Domain/query source separation supports later portability work, but
`libtmux/query` currently loads the core and its selected backend. There is no
independently loadable pure-domain system or broader portability claim.

### Separate acquisition from captured traversal

[`fetch-snapshot`](../api.md#fetch-snapshot-function) performs external reads
and returns a finite CLOS graph. Acquisition conveniences such as `fetch-panes`
also acquire that graph. Getters, relations, printing, projection and query
evaluation read retained state and perform zero tmux commands.

[`refresh`](../api.md#refresh-function) acquires a replacement observation.
Earlier objects retain their captured values. A global cache must not update
all references to an entity when another acquisition runs.

A snapshot records acquisition bounds and provenance. Its listings span
multiple commands, so it is not a transactional snapshot of a changing daemon.
Acquisition validates duplicate rows, references and graph invariants; bounded
retries share the original deadline and byte budget. Failure remains distinct
from a successful empty graph. See [capture contracts](../captures.md).

This choice makes repeated local queries predictable. It costs a complete
capture for the current convenience fetchers and requires an explicit refresh
when callers need newer state.

### Represent physical entities and contextual window links separately

Sessions, windows and panes are captured physical entities. A `window-link`
records the session, index, expected window and session-relative active state.
One physical window can have several links, including several in one session.

That distinction follows tmux's
[`server_link_window`](https://github.com/tmux/tmux/blob/3.8/server-fn.c#L289-L342)
and [`winlink` traversal in `cmd_list_panes_session`](https://github.com/tmux/tmux/blob/3.8/cmd-list-panes.c#L85-L93).
Contextual pane listings can repeat a physical pane through different links.
Acquisition normalizes physical entities while retaining every contextual link.
Session traversal can therefore return a physical window more than once.
Local filtering preserves the order and multiplicity supplied by its caller.

The OCaml core makes the same distinction through
[`Window.links` and `Window_link`](https://github.com/libtmux/libtmux-ocaml/blob/53a51bed2caa198be0fc3d81cb464e29d9f29403/lib/libtmux.mli#L245-L283).
Lisp expresses it with CLOS objects and fresh relation vectors. The extra class
prevents a physical window from acquiring a fictional single parent session.

### Bind operational identity to one client context and daemon generation

[`same-entity-p`](../api.md#same-entity-p-function) compares the model, client
context, generation and captured identity. Two clients have different contexts
even if they reach the same daemon. Attached-client identity belongs to one
observation; reusable target names do not prove continuity.

The Linux witness combines daemon PID and startup, socket device/inode,
kernel process-start identity and a retained pidfd. Acquisition binds listing
witnesses to their connection and checks continuity. Replacement invalidates
the generation. A window-link keeps its expected window because its index can
be renumbered or reused.

Named operations take the client explicitly, validate the selected observation,
and dispatch using its identity. They do not rerun a broad name query to choose
a mutation target. Live guards reduce stale-target mistakes but do not make
selection and mutation transactional. Cross-client refusal and explicit
`stale-target` conditions trade convenience for conservative targeting.

Use one client for an operation's acquisition and mutation. Applications can
serialize work through a client-owning worker and pass plain projections between
workers. A pooled replacement client cannot accept an earlier client's handle.
`same-entity-p` answers contextual identity, not universal cross-connection
equivalence. A future adoption operation would need to establish authority under
the receiving client; matching witness fields alone does not change this policy.

### Own mutable data at public boundaries

Public strings, relation containers, projections, query operands and inspection
results belong to the caller. They cannot expose mutable storage retained by a
snapshot or compiled filter. Entity objects may be shared across fresh result
containers. Deliberate mutation of private slots is outside the supported API.

[`entity-data`](../api.md#entity-data-function) returns finite ordinary data
with relationship identifiers, rather than recursively expanding the graph or
retaining hidden operational handles. Retaining one entity retains its snapshot
graph. Use projections for histories that need values without those references.
Remote paths stay reported strings: tmux may transform their representation,
and a decoder cannot recover information already lost upstream. They are not
filesystem identity or automatically suitable local filesystem arguments.

[`field-value`](../api.md#field-value-function) returns value and presence as
two values. Present false is `nil, t`; absence is `nil, nil`. Empty vectors and
empty strings retain their ordinary Lisp meanings. Unknown fields and unloaded
relations signal conditions instead of masquerading as absence.

Copies add allocation at public boundaries. Internal evaluators can read owned
storage directly; performance work must preserve the public ownership contract.

### Use ordinary sequences and compile a small declarative query language

Lists, vectors and genuine Lisp functions remain the foundation.
[`matching`](../query-api.md#matching-function) returns a fresh simple vector
in input order with duplicates preserved.
[`predicate`](../query-api.md#predicate-function) returns a function usable
with `funcall`, `remove-if`, `some` and other sequence facilities.

[`compile-filter`](../query-api.md#compile-filter-function) validates
keyword-headed query data against an explicit model/field/relation registry.
It owns a canonical expression and prepares native predicate closures. It
never evaluates query data as Lisp code. Limits bound input depth, visits,
membership, retained text and declarative evaluation. Inspection returns
defensive data; arbitrary native predicates remain application code.

Text equality uses `string=`; query comparison operands are native integers.
Captured numeric fields have separate wire bounds; a comparison operand can
lie outside that field's range. False comparisons are valid, scalar comparisons
fail on absence, and ordinary negation can include absent values. Empty AND is true;
empty OR and membership are false. ANY over an empty relation is false; ALL and
NONE are true. One nested child must satisfy an entire related conjunction.
The [query guide](../queries.md) owns the full operator contract.

This resembles OCaml's
[`Expr.Rel` and `Expr.compile`](https://github.com/libtmux/libtmux-ocaml/blob/53a51bed2caa198be0fc3d81cb464e29d9f29403/lib/libtmux.mli#L589-L604),
while Lisp validates model and operand types when `compile-filter` is called.
OCaml checks its typed builders through static types.

The optional eager QuerySet copies its input container and returns new values
from filtering and ordering. Sorting works on a private copy. `items` provides
portable sequence interoperability; custom SBCL sequence extensions are not
required. Strict `one` and `one-or-none` establish uniqueness before returning
a target. Current selectors validate the whole bounded input and report exact
counts; no current selector emits a lower-bound count. `where-if` and `order-by`
accept function objects and symbols naming global functions. Each designator
is resolved once before traversal or sorting; later redefinition affects a
subsequent operation. Macros and special operators are not function designators.

Declarative filters target the closed registered capture schema. A downstream
`field-value` method does not replace its private resolved accessor. Compose
application models through ordinary functions. Public operator/model registration
would require type, presence, ownership and serialization contracts together.

Compiled filters retain resolved descriptors. Their reported registry version
is descriptive; evaluation does not enforce a version compatibility check.
Recompile filters after incompatible library or schema changes. Functions and
inert data remain the public contract. An optional compiler macro could diagnose
literal forms without replacing runtime validation or evaluating query data;
compile-time checking is not implemented.

### Present conditions without inventing recovery guarantees

Conditions retain query diagnostics, causes, targets and command evidence.
Current inheritance is coarse: `query-limit-exceeded` also covers execution of
a valid filter, while `output-limit-exceeded` inherits `outcome-unknown` even
when raised for captured row/entity limits. Inspect the operation and
[`error-outcome`](../api.md#error-outcome-function); ancestry alone does not
prove that a mutation was dispatched. Separating resource exhaustion from
effect uncertainty is a follow-up API decision.

No library-specific restarts are currently installed. Recovery additions must
have a defined scope, such as replacing local query data, selecting an already
captured candidate explicitly, or retrying owned cleanup. A restart must not
turn failed acquisition into an empty graph, replace stale authority silently,
or re-dispatch a mutation. Fresh acquisition is a separate visible action.

### Supervise subprocesses with explicit scopes and bounded outcomes

[`with-client`](../api.md#with-client-function) uses an original hidden binding
and `unwind-protect`, supports declarations and preserves multiple values.
[`close-client`](../api.md#close-client-function) releases client-owned
processes, descriptors and streams. Daemon termination is a separately named
operation. Captured objects remain useful after closure.

The synchronous backend services input and both output streams concurrently
through nonblocking descriptors. One operation owns a client at a time;
independent operations use independent clients. Deadlines, combined byte caps
and cancellation govern supervised work. Public calls block their caller.

SBCL creates the process group for redirected stdin; see its
[`setpgrp` launch path](https://github.com/sbcl/sbcl/blob/sbcl-2.6.10/src/runtime/run-program.c#L327-L346).
The fixed Bash/FIFO launcher delays target exec until Lisp retains and verifies
the pidfd/group and admits dispatch under cancellation and deadline checks.
It passes argv as positional arguments without interpolating caller data into
shell source. The backend accepts trusted native ELF executables and normalizes
its launch environment. Its process-group scope does not contain
descendants that deliberately escape or force an uninterruptible kernel call
to return. See [transport limits](../transport.md#supported-process-boundary).

Keep that gate until a replacement preserves dispatch admission and cleanup.
glibc's `pidfd_spawn` can create a pidfd atomically, but its
[`CLONE_VFORK` sequencing](https://github.com/bminor/glibc/blob/glibc-2.40/sysdeps/unix/sysv/linux/spawni.c#L31-L47)
allows target exec before control returns to Lisp. It also needs explicit file
actions, signal policy, reaping and partial-failure ownership. Symbol availability
does not establish equivalent cancellation or dispatch attribution.

The low-level timer starts after argument preparation and executable inspection.
It charges synchronous setup/launch but cannot interrupt those calls. Poll and
gate checks enforce admission and supervised execution. Within the 500 ms stop
allowance, KILL is scheduled at 50 ms; final cleanup may wait another 500 ms for
child exit. Client close has a 750 ms owner-join allowance; lock acquisition
and retained cleanup are additional. These fixed intervals are not hard upper
bounds on caller wall time. Named operations share their acquisition/dispatch/
observation budget; workspace apply currently gives each core operation its own.

Cleanup failure after normal completion signals a condition. During an existing
error or nonlocal exit, the original exit is preserved and the secondary
failure is retained. Incomplete cleanup remains owned and inspectable.

Live clients are not saved-image resources. Close them before saving an image;
restoration would require reopening and rechecking backend facilities. The
[SBCL image contract](https://github.com/sbcl/sbcl/blob/sbcl-2.6.10/src/code/save.lisp#L197-L213)
does not preserve open-stream state and requires other threads to stop before
saving. Automatic cache reset, restored operational authority and retained
filter/snapshot compatibility across image or library upgrades are unqualified.

### Preserve interpreter boundaries and uncertain mutation outcomes

Outer argv execution, tmux command parsing, tmux formats, literal text and pane
shell source are separate input boundaries. Passing argv alone does not make
tmux arguments literal: for example,
[`cmd_rename_window_exec`](https://github.com/tmux/tmux/blob/3.8/cmd-rename-window.c#L46-L61)
format-expands its name. Named operations use tested encoders for the relevant
boundary. Arbitrary captured terminal output remains bytes unless decoding is
explicitly requested.

[`command-outcome`](../api.md#command-outcome-type) retains dispatch phase,
status, diagnostics, arguments and timing. A mutation can succeed while its
replacement observation fails; these remain separate results. A nonzero exit
does not promise rollback. An interrupted dispatched mutation can have an
unknown outcome and must not be retried automatically.

Attached terminal-client operations preserve the distinction between a server
request and frontend completion. Switching can acquire a replacement observation;
redraw, detach, suspend and lock acknowledge requests. A detach receipt is not
process-exit proof, and a lock receipt is not authentication. Tests use ordinary
owned PTY clients with separate process/FIFO evidence. Switching preserves the
destination environment by default: tmux's
[`cmd_switch_client_exec`](https://github.com/tmux/tmux/blob/3.8/cmd-switch-client.c#L157-L165)
updates it unless `-E` is supplied. Environment update is an explicit option.

Blocking server commands also need daemon-side lifecycle review: retiring the
owned subprocess does not dispose of tmux's command queue. The named
[`wait-for`](../api.md#wait-for-function) helper admits blocking wait/lock only
from 3.8, where
[`cmd_wait_for_client_lost`](https://github.com/tmux/tmux/blob/3.8/cmd-wait-for.c#L483-L515)
removes disconnected waiters. Signal/unlock retain the core floor. Granted
locks remain daemon state; cancellation and client closure do not unlock them.
Foreground `run-shell` remains unqualified: its
[`completion callback`](https://github.com/tmux/tmux/blob/3.8/cmd-run-shell.c#L291-L308)
can clear a waiting flag after client loss, while the removed client's queue
has no later server-loop pump. The API must distinguish the daemon's job
from retained command state.

`source-file` also remains unqualified on the supported releases. During an
ordinary client's pending file read,
[`file_fire_done_cb`](https://github.com/tmux/tmux/blob/3.8/file.c#L156-L165)
can free the file while skipping its consumer after client loss. The source
command then retains its waiting continuation and queue/client references.
Parse-only mode uses that same lifetime. Admission needs bounded input and
proven release of those references; reaping the library's CLI is insufficient.

Raw [`run-command`](../api.md#run-command-function) is an explicit escape hatch.
It does not provide named-operation target validation or imply that an
unqualified control-mode route is supported.

### Keep daemon bootstrap separate from client connection

Named acquisition and creation use `-N` and require an existing daemon.
Opening or closing a library client does not acquire ownership of that daemon.
Raw commands remain caller-controlled and can explicitly start one; they do not
constitute a managed bootstrap API.

Managed bootstrap needs a separate environment, configuration and ownership
contract. tmux
[seeds its global environment from its starter](https://github.com/tmux/tmux/blob/3.8/tmux.c#L418-L423).
Blindly reusing the transport's forced locale would change pane defaults.
The initial design uses an owned foreground `-D` child, explicit `/dev/null`
configuration and a new socket in a private directory. It must not adopt an
existing endpoint: [`client_connect`](https://github.com/tmux/tmux/blob/3.8/client.c#L104-L175)
can connect before considering startup. Copy the selected environment, preserve
the caller's locale, and clear inherited tmux selectors and socket-activation
settings. The Bash gate's shell metadata is not byte-transparent forwarding.

An attribute event after tmux's
[`initial socket update`](https://github.com/tmux/tmux/blob/3.8/server.c#L337-L372)
can trigger a readiness check. Readiness requires completed IPC identifying the
still-owned child; neither exec nor pathname creation proves it. Initial support
uses empty configuration because completion of arbitrary configuration does not
establish error-free application.

The daemon needs its own persistent owner and continuous pipe service, separate
from ordinary clients. Closing a client must still leave it running. Owner
shutdown must terminate and reap its child, then remove only the recorded socket
entry after checking its type and identity; normal tmux exit leaves that path.
Partial startup and failed cleanup retain the same ownership obligation. Source
review and bounded startup probes support this design; persistent lifecycle and
failure recovery remain unimplemented and unqualified.

### Keep optional systems and consumer policy explicit

| ASDF system | Responsibility | Additional dependency |
| --- | --- | --- |
| `libtmux` | Captures, subprocesses, operations and conditions | UIOP; SBCL/Linux backend facilities |
| `libtmux/query` | Registry-backed local expressions and QuerySets | Core |
| `libtmux/regex` | Explicit CL-PPCRE search and full-match operators | Query and CL-PPCRE |
| `libtmux/json` | Bounded versioned query interchange | Query and Jzon |
| `libtmux/workspace` | Owned declarations, local plans and explicit apply | Core and Jzon |
| `libtmux/workspace/cli` | Explicit-endpoint command-line adapter | Workspace |
| `libtmux/tests` and test subsystems | Interactive and automated semantic tests | FiveAM and the tested systems |

Core and query loading must work without optional libraries. Regex semantics
belong to CL-PPCRE; query visit limits do not interrupt a scanner. JSON uses
the native `libtmux.lisp.filter/1` schema, resolves registered names and rejects
unknown or duplicate members. It does not serialize arbitrary closures or
claim compatibility with another port's evaluator. See
[interchange contracts](../query-interchange.md).

These systems isolate dependencies within one coordinated release. They share
private registry/compiler internals; they are not independently versioned
plugins. The optional regex hook is private. A public extension protocol needs
an external consumer and a deliberate compatibility contract.

Workspaces consume core operations. Validation and planning are local; apply
acquires fresh state and retains individual outcomes. Exact topology reuse can
avoid mutations, but a batch is not a transaction or process supervisor.
[tmuxp's `ClassicWorkspaceBuilder`](https://github.com/tmux-python/tmuxp/blob/v1.76.0/src/tmuxp/workspace/builder/classic.py#L115-L137)
is a companion precedent for a workspace product over libtmux. The Lisp
[workspace contract](../design/workspace-v1.md) defines its own narrower scope.
Its native schema does not accept tmuxp documents. A displayed plan is a preview:
apply captures and plans again. Topology reuse does not prove command, directory,
layout or declaration provenance equality. Total-application deadlines, drift
metadata and broader reconciliation remain separate unfinished work.

### Qualify control mode and source filtering before exposing them

Persistent control is a separate intended system. It needs one transport
reader, serialized writes, bounded queues, byte-preserving output, distinct
timeout/end/loss/cancellation results and callbacks outside the reader.
Acknowledgment and operation-specific completion must remain distinct. Reconnect
requires a new generation and recapture; it cannot imply replay.

tmux's [`control_write_guard`](https://github.com/tmux/tmux/blob/3.8/control.c#L522-L548)
defines reply guards. Older daemon initialization needs separate scrutiny:
[`server_client_check_exit`](https://github.com/tmux/tmux/blob/3.3a/server-client.c#L2423-L2442)
can enter control cleanup, while
[`server_client_dispatch_identify`](https://github.com/tmux/tmux/blob/3.3a/server-client.c#L2969-L2987)
starts control state only after identification completes. The proposed one-shot
control acquisition route remains disabled. Harmless parser/relay experiments
cannot qualify a live daemon path, kernel premise or portable transport.

Source filtering is also pending. It belongs at an explicit acquisition
boundary. A supported translation must admit every locally accepted object,
preserve required relationships, and recheck locally. Unsupported expressions
must fall back locally. The current complete graph cannot discard nonmatching
rows: they may be siblings, reverse links or related clients exposed by captured
getters. Intersecting filtered IDs with a later capture also loses matches when
state changes between those observations.

Native evaluation success needs its own evidence. Starting in tmux 3.7,
[`format_check_time`](https://github.com/tmux/tmux/blob/3.7/format.c#L4196-L4205)
enforces a 100 ms format budget. Failed expansion can become empty, and
[`list-panes`](https://github.com/tmux/tmux/blob/3.8/cmd-list-panes.c#L141-L163)
treats a false expansion as a row to omit. Local rechecking cannot recover that
row. Bounded syntax alone does not prevent host scheduling delays or an inner
failure from producing an apparently Boolean result. Pruning remains unqualified
until both complete relationships and failure-aware evaluation are established.

A private whole-expression compiler and fixed-fixture comparisons can establish
a bounded scalar subset without changing acquisition. Native numeric `e`
expressions use floating-point parsing, so their exact field/operand domain must
be proved separately from Lisp's integer semantics. Non-pruning annotations may
help conformance work; they are not reduced acquisition or authoritative runtime
selection. Local [`matching`](../query-api.md#matching-function) remains the
authority over a complete capture and must never acquire.

## Security boundary

Trust the chosen executable and the supported daemon configuration. A selected
socket limits addressing; it supplies neither a sandbox nor exclusive ownership.
Process/socket witnesses are operating-system evidence, not cryptographic
authentication. The library does not defend against a privileged hostile host
or arbitrary interference with its private state.

Aliases and hooks are ambient daemon behavior; a nominal read can activate
configured effects. The
[command-policy contract](../operations.md#command-aliases-and-daemon-configuration)
defines refusals and the race after auditing aliases. Guards compare supported
server/target facts, not every captured value; attached-client targets lack a
dispatch-side target guard. Keep guarded dispatch distinct from general
compare-and-swap or transaction claims. The transport's forced locale and
sanitized startup environment are part of its contract, not transparent
environment forwarding.

## Consequences

Applications gain stable retained observations, explicit I/O and native Lisp
composition. The cost is copying public mutable values, retaining snapshots
and refreshing deliberately. Conservative client identity prevents convenient
cross-client targeting. A complete graph costs more than a specialized listing.

The successful no-retry paths have these tmux launch counts, excluding client
open, the caller's earlier target capture and hook/payload subprocesses:

| Operation | Launches |
| --- | ---: |
| Nonempty `fetch-snapshot` or convenience fetch | 5 |
| Empty live-daemon snapshot | 4 |
| `rename-window`, default observation | 11 |
| `rename-window`, observation disabled | 6 |
| `capture-pane` | 6 |
| `new-session`, including observation | 8 |
| `new-window` or `split-pane`, including observation | 11 |

The nonempty capture performs one alias audit, an initial witness, a session
listing, a batch of three remaining listings and a closing witness. Launch counts establish work, not latency. Bash execs
the target in the same supervised child. Full preflight also makes a targeted
mutation depend on obtaining a valid complete graph during unrelated churn.

Batching non-waiting listings reduces launches without changing capture semantics. tmux
[`cmdq_next`](https://github.com/tmux/tmux/blob/3.8/cmd-queue.c#L706-L785)
drains queued work, but hooks can intervene and captured values such as a pane's
cwd involve an
[external process lookup](https://github.com/tmux/tmux/blob/3.8/osdep-linux.c#L64-L85).
Batching does not freeze every observed value. Any optimization must preserve
audit ordering, framing, witness checks, empty-server handling, bounds and
contradiction detection. Narrow preflight and deferred creation observation
also require explicit return/outcome and target-validation contracts.

The batch combines window-link, pane and attached-client listings. Distinct
witness tags identify each block, including an empty client block; all three
witnesses are verified. Tag widths preserve the existing field-limit behavior.
The alias audit, fresh initial witness, separate session listing and fresh
closing witness remain. Nonempty acquisition uses five launches; the empty path
uses four. A two-launch prototype that reuses an earlier witness does not
establish equivalent fresh acquisition. Further reductions require separate
failure, shared-budget and generation evidence.

The narrow process backend gives ownership and cleanup concrete semantics, but
requires Linux capabilities and a trusted executable. Adding another backend
is implementation work, not a packaging change. Bounded transport does not
bound unrestricted application predicates or CL-PPCRE execution.

Optional systems reduce mandatory dependencies while adding combinations to
test. Explicit uncertain outcomes require callers to inspect evidence before
recovery. Control subscriptions, server-side filtering and full suite support
remain unavailable until their own behavioral gates pass.

## Rejected alternatives

- Mutable live getters would hide repeated acquisition inside ordinary graph
  traversal and make retained query inputs change unexpectedly.
- One parent session per window or deduplication by numeric ID alone would lose
  window-link context and cross-server identity.
- Evaluating query data or persisting arbitrary accessors would bypass the
  declared grammar. Convenience macros that construct that same inert data
  remain possible; they are not needed for the ordinary function contract.
- A mandatory custom sequence protocol would restrict native interoperability.
- Implicit retries, process exit as sole mutation proof and automatic daemon
  teardown would erase uncertainty or exceed resource ownership.
- An unqualified control relay or textual source-filter translation would turn
  a research premise into an unsupported public guarantee.

## Validation obligations

Decisions need tests at their actual boundary: local processing performs no
I/O; returned mutable values cannot change retained state; linked windows keep
their context; replacement generations reject stale operations; false and
absence remain distinct; command encoding survives hostile punctuation; and
cleanup works on normal return, error and nonlocal exit.

FiveAM supports focused REPL redefinition and reruns as well as CI. Shipped
examples execute against owned isolated sockets and from the source archive.
Generated references come from actual public declarations and docstrings.
Documentation records library and exporter provenance separately. Shared-site
builds and previews remain distinct from publication.

The selected tmux floor is 3.3a; plain 3.3 is rejected. The required final
Linux matrix is 3.3a, 3.4, 3.5, 3.5a, 3.6, 3.6a, 3.6b, 3.7, 3.7a, 3.7b, 3.7c
and 3.8. Endpoint CI or source catalogs do not substitute for full integrated
acceptance. Timed test loops are verification costs, not performance results.
Benchmarks must separately report workload, acquisition count, versions,
distributions and allocations. Measure small and larger graphs, repeated local
queries, mutations with and without observation, workspace sequences and graph
retention after GC. Component timings are not library timings; one host does
not qualify another platform or a tail-latency guarantee.

## When to reconsider

Reconsider the backend when another Lisp/OS can satisfy the same ownership,
cancellation and identity contracts. Reconsider complete-graph acquisition
after measurements establish a workload needing narrower captures without
weakening relation semantics or consistency reporting.

Reconsider copying or predicate preparation after allocation and execution
profiles identify a material cost and an alternative preserves public
ownership. Reconsider control admission when exact supported daemon and host
profiles pass end-to-end qualification. Reconsider source filtering only after
fixed-fixture equivalence proves that it cannot discard a local match.

A new wire schema, identity policy, implicit-I/O convention or product boundary
requires a successor ADR or an explicit amendment with migration consequences.

## References and source versions

The structure follows the Python project's
[ADR 0001 at v0.1.0a22](https://github.com/tmux-python/libtmux-mcp/blob/v0.1.0a22/docs/dev/adr/0001-capability-model.md):
context, decisions, consequences, rejected alternatives and reconsideration.

External source links use release tags where available: tmux 3.3a/3.8, SBCL
2.6.10, glibc 2.40, Linux 6.9, Python libtmux v0.62.0, tmuxp v1.76.0 and the
Python ADR v0.1.0a22. The OCaml repository
has no release tags; its links use the verified immutable core revision instead.
These versions identify the compared sources, not inherited compatibility
claims. Local contracts link to this repository's API and owning guides so they
can evolve with the implementation.
