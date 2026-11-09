# Owned workspace design

The accepted design for workspace/2 adds logical IDs, durable ownership records,
drift inspection and explicit additive reconciliation. **Workspace/2 is not yet
implemented.** The current constructor, file loader and CLI implement the
[workspace/1 contract](workspace-v1.md), including topology-only reuse.
This document records the implementation target and its remaining gates.

## Identity and declarations

Workspace/2 requires a bounded ASCII ID for the workspace, session, every window
and every pane. IDs remain stable when names change. Names, mutable indexes,
paths and current processes do not identify an owned entity. A distinct schema
preserves existing workspace/1 behavior; it does not silently adopt its sessions.

Creation inputs keep their current meanings: literal argv, explicit shell
source, session environment, cwd defaults and named or custom layouts. Changed
creation-only inputs on an existing entity are unsupported declaration drift.
They do not justify respawning a process or pretending its environment changed.

The committed mapping retains physical session/window/pane IDs, contextual
session/index/window links and exact realized layouts. A new client resolves
those IDs through its own fresh capture and daemon witness. Stored data does
not recreate an operational handle or bypass
[client affinity](../captures.md#identity-and-refresh).
Declared custom layout text remains separate from realized geometry and IDs.

## Publication and bounded records

Each workspace has a permanent server-scoped control option. The root ID is
hex-encoded before forming its namespace, so IDs containing dots cannot overlap
another workspace's prefix. The control value has explicit idle and busy states
and a committed revision; a busy writer also has a fresh token. Genesis claims
busy state through native absent-only initialization. There is no idle genesis,
lease expiry, automatic claim stealing or mutation replay.

One writer conditionally acquires an exact idle revision, writes pending intent,
applies core operations, verifies the graph and writes a complete immutable
revision. Conditional publication is its last mutation. Subsequent reads report
publication separately from failed observation or a newer writer's progress.
Every command outcome remains inspectable.

Records use a closed JSON grammar and immutable hex chunks. Defaults bound a
record to 1 MiB, 512 chunks, depth 32 and 65,536 nodes. The final encoded command
still obeys core's 16,000-byte argv limit. A maximum-sized valid declaration is
not a promise that every reconciliation fits a configured deadline or envelope.
No Lisp reader, evaluation, name interning or serialized closure is involved.

Genesis needs a bounded reserved-prefix inventory through
[show-options-text](../api.md#show-options-text-function), with server scope and
hooks included. A named read alone cannot detect orphan keys. The `-H` flag
matters: [tmux 3.8's printer](https://github.com/tmux/tmux/blob/3.8/cmd-show-options.c#L349-L368)
omits some user entries otherwise. Unreferenced revisions and malformed or
partial records cause refusal. They do not become an empty workspace.

Only the next writer collects garbage, under its busy claim and before domain
changes. It removes the bounded known previous revision and old pending intent.
It never deletes the permanent control, current revision or unknown keys.
Publication has no outgoing cleanup race with the next writer. No-op application
performs no hidden maintenance.

## Acquisition and local planning

An explicit acquisition returns the captured graph, decoded records, group and
geometry facts, read outcomes and observation interval. Matching idle control
reads bracket the work; one changed-read restart shares the original budgets.
This remains an observation over time, not an atomic snapshot.

Planning consumes that acquired observation locally. A snapshot alone does not
prove ownership. Plans distinguish declaration changes from observed drift and
retain ordinary owned data. Inspection, traversal and projection do no I/O.

Default application refuses drift. Explicit `--reconcile` will add declared
windows or panes, rename mapped sessions/windows, and apply requested layout
changes or repair observed layout drift. It preserves unrelated windows and
links. Removal, process replacement, forced adoption, index swaps and missing
or rebound owned IDs are refused. Unmanaged panes prevent splits and layout
changes in their containing window.

Pane additions can precede, interleave or follow existing panes while preserving
their relative order. This requires regular, non-full-size splits: tmux inserts
them [before or after the selected pane](https://github.com/tmux/tmux/blob/3.3a/window.c#L719-L742).
Floating splits have a [different insertion rule](https://github.com/tmux/tmux/blob/3.8/window.c#L1148-L1171).
Geometry plans therefore require an unzoomed window and complete nonfloating,
nonmodal pane facts, alongside the unmanaged-pane and sharing checks. Rename
and no-op inspection do not require geometry changes.

The private reader acquires these facts in one additional guarded listing.
Exact source profiles use floating flags from tmux 3.7 and modal flags from
3.8; earlier profiles use literal false only for source-proven absent features.
Empty flags never mean false. Zoomed windows remain ineligible even when all
reported floating flags are false: tmux can [restore hidden layout cells while
unzooming](https://github.com/tmux/tmux/blob/3.8/window.c#L1022-L1052).
Rows must cover every captured physical pane and agree across linked-window
contexts. Their raw bytes and decoded rows consume the original read budgets.
Installing a replacement graph clears the previous graph's group and geometry
facts before acquiring new ones. Failed replacement capture retains the earlier
graph and its facts together.
These facts describe an observation; dispatch must check the live state again.

## Live guards and incomplete work

Every mutation needs a final live control-token check, exact session identity,
ungrouped context and appropriate exclusive-window checks. Splits and layouts
also compare the fresh physical pane sequence and count, require an unzoomed
window and reject floating or modal panes. Grouped sessions can
propagate window creation; a prior snapshot check alone cannot prevent that.
These [tmux group fields](https://github.com/tmux/tmux/blob/3.8/format.c#L2989-L2996)
are checked again at dispatch.

Private preconditions belong adjacent to the payload in core's existing witness
and target guard chain. Refusal needs its own receipt and retained non-dispatch
outcome. A complete predicate uses a final conditional permission literal so
formatter expiration refuses the command. Generated syntax and recursion depth
remain independently bounded; this is not a general formatter-success API or
permission to enable held source filtering.

Busy or uncertain work remains incomplete. Pending intent is immutable, and
returned IDs remain process-local until the committed record exists. A crashed
publisher can therefore leave effects without a durable returned ID. The
inspection path must expose that gap and all retained causes and outcomes.

Recovery initially permits externally quiesced retirement, not head restoration
or rewind. Stop and join publishers and readers, identify and retire the managed
session through explicit core operations, then retire only inspected known keys.
If an uncertain creation cannot be identified or absence cannot be established,
recovery remains refused. The library never repeats an uncertain mutation.

## Remaining qualification

The private declaration and record codec implements logical ID validation,
canonical data, bounded chunks and declaration/mapping consistency. It preserves
JSON null, false and container distinctions. These pure data checks do not prove
that a graph exists or that a client may operate on its IDs. The current public
constructor and CLI still refuse workspace/2.

The private state reader now acquires the namespace, referenced bundles, graph,
session-group facts and complete geometry facts explicitly. One operation owner,
deadline, raw-byte allowance and metadata record ledger cover both attempts.
A changed control can
restart the read once; busy or invalid state stays a failure. Closing inventory
and control checks also apply to vacancy. Missing physical identities and changed
links fail; names, layouts and unmanaged entities remain observations for the
future drift planner. Outcome retention includes failed reads. Inspection is
local and returns owned data. This is an interval observation, not a transaction.
Failure conditions retain already acquired metadata, graph, group facts, original
context and interval. A later read failure does not replace the primary metadata
error. Early busy refusal can have no acquired graph or decoded bundle; richer
explicit busy inspection remains part of the complete consumer contract.

The complete contract has independent source review. Owned stock endpoint
probes establish claim contention, wrong-token refusal, actual payload-hook
changes, pane-loop order and namespace discovery. An instrumented pinned
formatter establishes the scalar expiry case and final-literal refusal.
These are mechanism checks; they do not qualify a workspace/2 implementation.

The core now has a private dispatch-precondition adapter; workspace guard
composition remains required. Other gates are pure drift planning,
creation/publication/reconciliation, complete busy inspection,
installed CLI/examples and complete native compatibility. The main
[architecture decision](../adr/0001-native-common-lisp-engine.md#keep-optional-systems-and-consumer-policy-explicit)
keeps this consumer separate from core and preserves unfinished acceptance.
