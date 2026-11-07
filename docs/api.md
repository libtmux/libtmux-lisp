# Public API

Generated from live package documentation and function signatures by
`mise run docs`. Edit source docstrings; `mise run check` detects drift.

[Guide index](index.md) · [Field reference](fields.md) · [Tutorial](tutorial.md)

Native Common Lisp captured tmux graphs and explicit external operations.
OPEN-CLIENT/WITH-CLIENT establish connection scopes without starting a daemon.
FETCH-SNAPSHOT acquires sessions, physical windows, panes, window links and
attached clients. Captured getters, traversal and ENTITY-DATA are local and
remain usable after closure; captured strings and containers are owned copies. REFRESH returns
a new observation. Named mutators take CLIENT first and return COMMAND-OUTCOME;
OUTCOME-VALUE and FIELD-VALUE return value and presence as two values.
Operations are synchronous, bounded and cancellable, with one active operation
per client. Typed LIBTMUX-ERROR conditions retain diagnostic outcome and cause.
Closing a client releases owned resources and leaves the daemon alive.
See docs/index.md for the tutorial, API reference and current capability limits.

## Functions and macros

- [active-p](#active-p-function)
- [break-pane](#break-pane-function)
- [cancel](#cancel-function)
- [cancelled-p](#cancelled-p-function)
- [capture-pane](#capture-pane-function)
- [capture-pane-bytes](#capture-pane-bytes-function)
- [clear-history](#clear-history-function)
- [client-cleanup-failures](#client-cleanup-failures-function)
- [client-open-p](#client-open-p-function)
- [clients](#clients-function)
- [close-client](#close-client-function)
- [copy-mode](#copy-mode-function)
- [current-command](#current-command-function)
- [current-path](#current-path-function)
- [dead-p](#dead-p-function)
- [delete-buffer](#delete-buffer-function)
- [entity-data](#entity-data-function)
- [entity-model](#entity-model-function)
- [error-actual-version](#error-actual-version-function)
- [error-cause](#error-cause-function)
- [error-client](#error-client-function)
- [error-commands](#error-commands-function)
- [error-feature](#error-feature-function)
- [error-field](#error-field-function)
- [error-message](#error-message-function)
- [error-model](#error-model-function)
- [error-outcome](#error-outcome-function)
- [error-required-version](#error-required-version-function)
- [error-setting](#error-setting-function)
- [error-target](#error-target-function)
- [fetch-clients](#fetch-clients-function)
- [fetch-panes](#fetch-panes-function)
- [fetch-sessions](#fetch-sessions-function)
- [fetch-snapshot](#fetch-snapshot-function)
- [fetch-windows](#fetch-windows-function)
- [field-value](#field-value-function)
- [height](#height-function)
- [id](#id-function)
- [index](#index-function)
- [join-pane](#join-pane-function)
- [last-pane](#last-pane-function)
- [last-window](#last-window-function)
- [link-window](#link-window-function)
- [list-buffers](#list-buffers-function)
- [load-buffer](#load-buffer-function)
- [make-cancellation-token](#make-cancellation-token-function)
- [move-pane](#move-pane-function)
- [move-window](#move-window-function)
- [name](#name-function)
- [new-session](#new-session-function)
- [new-window](#new-window-function)
- [next-layout](#next-layout-function)
- [next-window](#next-window-function)
- [open-client](#open-client-function)
- [outcome-arguments](#outcome-arguments-function)
- [outcome-cleanup-failures](#outcome-cleanup-failures-function)
- [outcome-elapsed](#outcome-elapsed-function)
- [outcome-exit-code](#outcome-exit-code-function)
- [outcome-observation-error](#outcome-observation-error-function)
- [outcome-phase](#outcome-phase-function)
- [outcome-reason](#outcome-reason-function)
- [outcome-status](#outcome-status-function)
- [outcome-stderr](#outcome-stderr-function)
- [outcome-stdout](#outcome-stdout-function)
- [outcome-value](#outcome-value-function)
- [panes](#panes-function)
- [paste-buffer](#paste-buffer-function)
- [pipe-pane](#pipe-pane-function)
- [previous-layout](#previous-layout-function)
- [previous-window](#previous-window-function)
- [provenance](#provenance-function)
- [refresh](#refresh-function)
- [rename-session](#rename-session-function)
- [rename-window](#rename-window-function)
- [resize-pane](#resize-pane-function)
- [resize-window](#resize-window-function)
- [respawn-pane](#respawn-pane-function)
- [respawn-window](#respawn-window-function)
- [rotate-window](#rotate-window-function)
- [run-command](#run-command-function)
- [same-entity-p](#same-entity-p-function)
- [save-buffer](#save-buffer-function)
- [select-layout](#select-layout-function)
- [select-pane](#select-pane-function)
- [select-window](#select-window-function)
- [send-keys](#send-keys-function)
- [send-prefix](#send-prefix-function)
- [send-text](#send-text-function)
- [session](#session-function)
- [sessions](#sessions-function)
- [set-buffer](#set-buffer-function)
- [show-buffer](#show-buffer-function)
- [split-pane](#split-pane-function)
- [swap-panes](#swap-panes-function)
- [swap-windows](#swap-windows-function)
- [title](#title-function)
- [tmux-version](#tmux-version-function)
- [unlink-window](#unlink-window-function)
- [width](#width-function)
- [window](#window-function)
- [window-links](#window-links-function)
- [windows](#windows-function)
- [with-client](#with-client-function)


<a id="active-p-function"></a>

### active-p

`(active-p entity)`

Return captured active state and presence, without I/O. False is NIL,T.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type), [window-link](#window-link-type).

<a id="break-pane-function"></a>

### break-pane

`(break-pane client pane source-link session index &key name (detached t) (observe t) cancel-token timeout output-limit)`

Break PANE from SOURCE-LINK into SESSION's free INDEX; return an outcome.
SOURCE-LINK fixes the session context when breaking the window's only pane;
tmux moves that link instead of creating another physical window. NAME is
literal. DETACHED defaults true. OBSERVE supplies the destination window link.
The pane keeps its identity. Signals INVALID-ARGUMENT, STALE-TARGET or an
operational condition. Occupied indexes are never overwritten.

[Source](../src/placement.lisp)

<a id="cancel-function"></a>

### cancel

`(cancel token)`

Cancel registered operations and return true only for the first request.
Cancellation wakes each active owner. It does not wait for completion or undo
a mutation. Inspect the operation's outcome and dispatch phase.

[Source](../src/transport.lisp)

<a id="cancelled-p-function"></a>

### cancelled-p

`(cancelled-p token)`

Return whether TOKEN has been cancelled, without external I/O.

[Source](../src/transport.lisp)

<a id="capture-pane-function"></a>

### capture-pane

`(capture-pane client pane &rest options)`

Read PANE now; return strict UTF-8 text and the diagnostic command outcome.
Preserve whitespace and trailing lines.
OPTIONS are the CAPTURE-PANE-BYTES options. Invalid UTF-8 signals DECODING-ERROR;
call CAPTURE-PANE-BYTES when byte preservation is required.

[Source](../src/operations.lisp)

<a id="capture-pane-bytes-function"></a>

### capture-pane-bytes

`(capture-pane-bytes client pane &key start end join-lines escape-sequences escape-controls alternate pending-output cancel-token timeout output-limit)`

Read PANE now; return owned output octets and the diagnostic command outcome.
START/END accept signed line numbers or :ALL for the corresponding history edge.
JOIN-LINES joins wrapped rows; ESCAPE-SEQUENCES retains terminal styles;
ESCAPE-CONTROLS asks tmux to render controls as octal; ALTERNATE selects its
alternate screen; PENDING-OUTPUT requests tmux's pending input bytes. Tmux owns
these capture modes and may reject unavailable combinations. Does not decode or
trim bytes. Signals STALE-TARGET or an operational condition with its outcome.

[Source](../src/operations.lisp)

<a id="clear-history-function"></a>

### clear-history

`(clear-history client pane &key cancel-token timeout output-limit)`

Clear PANE's retained tmux history; return a COMMAND-OUTCOME.
Captured observations remain unchanged. This does not promise to clear the
application's current screen. Signals STALE-TARGET or an operational condition.

[Source](../src/terminal-operations.lisp)

<a id="client-cleanup-failures-function"></a>

### client-cleanup-failures

`(client-cleanup-failures client)`

Return a fresh vector of secondary cleanup conditions, newest first. No I/O.

[Source](../src/client.lisp)

<a id="client-open-p-function"></a>

### client-open-p

`(client-open-p client)`

Return whether CLIENT's lifecycle is open; no tmux I/O.
An active operation may still cause CLIENT-BUSY when new work is attempted.

[Source](../src/client.lisp)

<a id="clients-function"></a>

### clients

`(clients observation)`

Return a fresh vector of attached-client observations, without I/O.
Preserve listing order and multiplicity, including repeated target names.

[Source](../src/model.lisp)

Applicable first argument types: [session](#session-type), [snapshot](#snapshot-type).

<a id="close-client-function"></a>

### close-client

`(close-client client)`

Reject new work, cancel active work and release owned resources.
The operation is idempotent and does not kill the daemon. A bounded teardown
failure signals CLEANUP-FAILED; the active owner still retains cleanup duty.

[Source](../src/client.lisp)

Applicable first argument types: [client](#client-type).

<a id="copy-mode-function"></a>

### copy-mode

`(copy-mode client pane &key exit page-up cancel-token timeout output-limit)`

Enter PANE's tmux copy mode, or EXIT it; return a COMMAND-OUTCOME.
PAGE-UP scrolls up on entry and cannot be combined with EXIT. This addresses an
existing pane and does not create an interactive terminal frontend. Signals
STALE-TARGET or an operational condition.

[Source](../src/terminal-operations.lisp)

<a id="current-command-function"></a>

### current-command

`(current-command entity)`

Return copied captured command text and presence, without I/O.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type).

<a id="current-path-function"></a>

### current-path

`(current-path entity)`

Return copied captured path text and presence, without local pathname conversion.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type).

<a id="dead-p-function"></a>

### dead-p

`(dead-p entity)`

Return tmux's captured dead flag and presence, without inferring it from PID.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type).

<a id="delete-buffer-function"></a>

### delete-buffer

`(delete-buffer client &key name cancel-token timeout output-limit)`

Delete the literal named buffer, or the current top buffer; return an outcome.
Named deletion requires a live tmux 3.4+ daemon because 3.3a can delete the top
buffer when the supplied name is missing. On 3.3a, an explicit NAME signals
UNSUPPORTED-CAPABILITY before payload dispatch; omission still deletes the top
buffer. A name identifies the buffer at dispatch, not an earlier incarnation.
Signals an operational condition on failure; never retries an unknown deletion.

[Source](../src/buffers.lisp)

<a id="entity-data-function"></a>

### entity-data

`(entity-data entity)`

Return a fresh finite plist of captured fields and provenance.
Relationships contain identifiers, not operational handles. Absent optional
fields are omitted; present false values remain in the plist. No tmux I/O.

[Source](../src/model.lisp)

Applicable first argument types: [entity](#entity-type).

<a id="entity-model-function"></a>

### entity-model

`(entity-model entity)`

Return :SESSION, :WINDOW, :PANE, :WINDOW-LINK or :CLIENT. No I/O.
:CLIENT denotes an attached tmux client observation, not a connection scope.

[Source](../src/model.lisp)

Applicable first argument types: [entity](#entity-type).

<a id="error-actual-version-function"></a>

### error-actual-version

`(error-actual-version condition)`

Return an owned copy of the live daemon release that failed the capability check.

[Source](../src/conditions.lisp)

<a id="error-cause-function"></a>

### error-cause

`(error-cause condition)`

Return the original underlying condition, or NIL. No I/O; may be shared.

[Source](../src/conditions.lisp)

Applicable first argument types: [libtmux-error](#libtmux-error-type).

<a id="error-client-function"></a>

### error-client

`(error-client condition)`

Return the connection client associated with the failure, or NIL.
A partially opened client may still own cleanup work; retry CLOSE-CLIENT if
cleanup failed. Reading this slot performs no I/O.

[Source](../src/conditions.lisp)

Applicable first argument types: [libtmux-error](#libtmux-error-type).

<a id="error-commands-function"></a>

### error-commands

`(error-commands condition)`

Return an owned vector of command spellings implicated in the configuration failure.

[Source](../src/conditions.lisp)

<a id="error-feature-function"></a>

### error-feature

`(error-feature condition)`

Return the unsupported capability's keyword identifier. No I/O.

[Source](../src/conditions.lisp)

Applicable first argument types: [unsupported-capability](#unsupported-capability-type).

<a id="error-field-function"></a>

### error-field

`(error-field condition)`

Return the requested field key, including an unregistered key. No I/O.
An invalid caller value is retained as supplied; it need not be a keyword.

[Source](../src/conditions.lisp)

Applicable first argument types: [field-unavailable](#field-unavailable-type).

<a id="error-message-function"></a>

### error-message

`(error-message condition)`

Return the failure's diagnostic string. No I/O; treat it as read-only.

[Source](../src/conditions.lisp)

Applicable first argument types: [libtmux-error](#libtmux-error-type).

<a id="error-model-function"></a>

### error-model

`(error-model condition)`

Return the captured model keyword implicated in a field failure. No I/O.

[Source](../src/conditions.lisp)

Applicable first argument types: [field-unavailable](#field-unavailable-type).

<a id="error-outcome-function"></a>

### error-outcome

`(error-outcome condition)`

Return retained COMMAND-OUTCOME evidence, or NIL before one exists.
Inspect dispatch phase and status before deciding how to recover. No I/O.

[Source](../src/conditions.lisp)

Applicable first argument types: [libtmux-error](#libtmux-error-type).

<a id="error-required-version-function"></a>

### error-required-version

`(error-required-version condition)`

Return an owned copy of the capability's minimum tmux release.

[Source](../src/conditions.lisp)

<a id="error-setting-function"></a>

### error-setting

`(error-setting condition)`

Return the daemon setting that violates a named command contract.
The captured diagnostic value may be shared; treat it as read-only. No I/O.

[Source](../src/conditions.lisp)

Applicable first argument types: [unsupported-configuration](#unsupported-configuration-type).

<a id="error-target-function"></a>

### error-target

`(error-target condition)`

Return the stale captured target, or NIL when unavailable. No I/O.

[Source](../src/conditions.lisp)

Applicable first argument types: [stale-target](#stale-target-type).

<a id="fetch-clients-function"></a>

### fetch-clients

`(fetch-clients client &rest options)`

Acquire a complete snapshot and return every attached-client row. OPTIONS go to FETCH-SNAPSHOT.

[Source](../src/capture.lisp)

<a id="fetch-panes-function"></a>

### fetch-panes

`(fetch-panes client &rest options)`

Acquire a complete snapshot and return physical panes once each. OPTIONS go to FETCH-SNAPSHOT.

[Source](../src/capture.lisp)

<a id="fetch-sessions-function"></a>

### fetch-sessions

`(fetch-sessions client &rest options)`

Acquire a complete snapshot and return its fresh session vector. OPTIONS go to FETCH-SNAPSHOT.

[Source](../src/capture.lisp)

<a id="fetch-snapshot-function"></a>

### fetch-snapshot

`(fetch-snapshot client &key cancel-token (timeout (slot-value client (quote timeout))) (output-limit (slot-value client (quote output-limit))) (row-limit 100000) (entity-limit 100000) (field-limit 1048576))`

Acquire an eager native graph; all later accessors on it are local.
TIMEOUT and OUTPUT-LIMIT bound the whole acquisition, including at most two
retries after contradictory observations. ROW-LIMIT bounds each listing;
ENTITY-LIMIT bounds the complete graph; FIELD-LIMIT bounds encoded field bytes.
No daemon is started. A live daemon with zero sessions yields empty vectors;
connection/listing failures remain errors. Closing CLIENT leaves this snapshot
usable. This is an interval observation, not a transactional snapshot.

[Source](../src/capture.lisp)

<a id="fetch-windows-function"></a>

### fetch-windows

`(fetch-windows client &rest options)`

Acquire a complete snapshot and return physical windows once each. OPTIONS go to FETCH-SNAPSHOT.

[Source](../src/capture.lisp)

<a id="field-value-function"></a>

### field-value

`(field-value entity field)`

Return a captured field and presence as two values, without I/O.
Present false is NIL,T; absence is NIL,NIL. Strings and relation containers are
copied. Unknown fields and unloaded relations signal FIELD-UNAVAILABLE.

[Source](../src/model.lisp)

Applicable first argument types: [entity](#entity-type).

<a id="height-function"></a>

### height

`(height entity)`

Return the positive captured height and presence, without I/O.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type), [window](#window-type).

<a id="id-function"></a>

### id

`(id entity)`

Return the captured identity, copying mutable components. No I/O.
Physical IDs are strings; a link ID is (session-ID index window-ID). Attached
client IDs identify rows within a single observation, not stable daemon clients.

[Source](../src/model.lisp)

Applicable first argument types: [entity](#entity-type).

<a id="index-function"></a>

### index

`(index entity)`

Return the nonnegative captured index and presence, without I/O.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type), [window-link](#window-link-type).

<a id="join-pane-function"></a>

### join-pane

`(join-pane client source destination &key (direction :vertical) size percent before full-size (detached t) (observe t) cancel-token timeout output-limit)`

Join SOURCE pane beside DESTINATION using tmux's join-pane command.
Arguments, outcomes, emptied-window effects and observation semantics match
MOVE-PANE. Both targets are captured physical panes. Signals STALE-TARGET or an
operational condition; a failed follow-up is distinct from mutation failure.

[Source](../src/placement.lisp)

<a id="last-pane-function"></a>

### last-pane

`(last-pane client window &key (observe t) cancel-token timeout output-limit)`

Select WINDOW's last active pane; return an outcome with that observed pane.
OBSERVE may omit follow-up acquisition. Tmux reports an error when no last
pane exists. Signals STALE-TARGET or an operational condition. Earlier
captures retain their original selection.

[Source](../src/selection.lisp)

<a id="last-window-function"></a>

### last-window

`(last-window client session &key (observe t) cancel-token timeout output-limit)`

Select SESSION's last active link; return an outcome with that observed link.
OBSERVE may omit follow-up acquisition. Tmux reports an error when no last
window exists. Signals STALE-TARGET or an operational condition. Earlier
captures retain their original selection.

[Source](../src/selection.lisp)

<a id="link-window-function"></a>

### link-window

`(link-window client source-link session index &key (detached t) (observe t) cancel-token timeout output-limit)`

Link SOURCE-LINK's physical window into SESSION at the free INDEX.
Return a COMMAND-OUTCOME with the new window link when OBSERVE is true.
SOURCE-LINK preserves the source session context, including tmux group rules.
DETACHED defaults true. Never overwrites an occupied index. Signals STALE-TARGET
or an operational condition; observation failure is retained separately.

[Source](../src/placement.lisp)

<a id="list-buffers-function"></a>

### list-buffers

`(list-buffers client &key (row-limit 10000) cancel-token timeout output-limit)`

Acquire buffer metadata; return a fresh simple vector of owned plists and an outcome.
Each plist has :BUFFER/NAME, :BUFFER/SIZE (bytes) and :BUFFER/CREATED (Unix
seconds). Preserve tmux's listing order; buffer names are mutable locators,
not captured entity identities. Empty listing returns #(). ROW-LIMIT bounds
decoding. Signals an operational or decoding condition with the raw outcome.

[Source](../src/buffers.lisp)

<a id="load-buffer-function"></a>

### load-buffer

`(load-buffer client path &key name cancel-token timeout output-limit)`

Load a file's bytes into a literal named or automatic buffer; return an outcome.
PATH is literal path text, not a format. Relative paths follow the tmux command
client's cwd. An empty file is tmux's no-op and preserves an existing buffer.
New names reject backslashes, ASCII controls and DEL before I/O.
Use SET-BUFFER for in-memory bytes. Signals INVALID-ARGUMENT or an operational
condition; a failure after dispatch may have an uncertain outcome.

[Source](../src/buffers.lisp)

<a id="make-cancellation-token-function"></a>

### make-cancellation-token

`(make-cancellation-token)`

Create a token for one or more operations. CANCEL is idempotent.

[Source](../src/transport.lisp)

<a id="move-pane-function"></a>

### move-pane

`(move-pane client source destination &key (direction :vertical) size percent before full-size (detached t) (observe t) cancel-token timeout output-limit)`

Move SOURCE pane beside DESTINATION; return an outcome with the moved pane.
DIRECTION is :HORIZONTAL or :VERTICAL. SIZE is cells; PERCENT is 1..100,
mutually exclusive with SIZE. BEFORE changes placement and FULL-SIZE spans the
window. Percent sizing retains tmux's version semantics: with FULL-SIZE, 3.3a
uses destination-pane dimensions and 3.8 uses whole-window dimensions. Use SIZE
for cell-based control. DETACHED defaults true.
An emptied source window is destroyed, including all its links. With DETACHED
false, tmux chooses the session context of the physical destination. OBSERVE
supplies a replacement source pane; its old observation retains its old window.
Signals STALE-TARGET or an operational condition.

[Source](../src/placement.lisp)

<a id="move-window-function"></a>

### move-window

`(move-window client source-link session index &key (detached t) (observe t) cancel-token timeout output-limit)`

Move SOURCE-LINK into SESSION at the free INDEX; return a COMMAND-OUTCOME.
Other links to the physical window survive. Removing a session's last link can
destroy that session, following tmux semantics. OBSERVE supplies the destination
link. DETACHED defaults true; occupied indexes are never overwritten. Signals
STALE-TARGET or an operational condition; older link observations stay unchanged.

[Source](../src/placement.lisp)

<a id="name-function"></a>

### name

`(name entity)`

Return the captured name and presence, without I/O; text is copied.

[Source](../src/model.lisp)

Applicable first argument types: [attached-client](#attached-client-type), [session](#session-type), [window](#window-type).

<a id="new-session-function"></a>

### new-session

`(new-session client &key name window-name width height cwd environment (command nil command-p) (shell-command nil shell-command-p) cancel-token timeout output-limit)`

Create a detached session on the selected live daemon; return a COMMAND-OUTCOME.
NAME, WINDOW-NAME and CWD are literal. WIDTH/HEIGHT are positive initial cell
dimensions through 65535. ENVIRONMENT, COMMAND and SHELL-COMMAND follow
NEW-WINDOW. OUTCOME-VALUE supplies the created session; acquisition failure is
retained separately. This operation requires an existing daemon and never
silently starts or replaces one. A separate bootstrap path remains in development.

[Source](../src/creation.lisp)

<a id="new-window-function"></a>

### new-window

`(new-window client session &key name index cwd environment (command nil command-p) (shell-command nil shell-command-p) (detached t) cancel-token timeout output-limit)`

Create a physical window in captured SESSION and return a COMMAND-OUTCOME.
NAME and CWD are literal strings. INDEX chooses a free link index; omission uses
tmux's next available index. DETACHED defaults true. ENVIRONMENT is a list/vector
of (name . value) string pairs. COMMAND is nonempty argv; SHELL-COMMAND is a
separate, mutually exclusive shell string. Omit both for tmux's default shell.
OUTCOME-VALUE supplies the resulting window; observation failure is separate.
Never replaces an occupied index or retries a mutation. Limits cover all I/O.

[Source](../src/creation.lisp)

<a id="next-layout-function"></a>

### next-layout

`(next-layout client window &key (observe t) cancel-token timeout output-limit)`

Cycle WINDOW to tmux's next layout; return an outcome and optional replacement.
Unzooms the window. Captured values remain unchanged. Signals STALE-TARGET or
an operational condition; follow-up acquisition failure is retained separately.

[Source](../src/geometry.lisp)

<a id="next-window-function"></a>

### next-window

`(next-window client session &key activity (observe t) cancel-token timeout output-limit)`

Select SESSION's next window link; return a COMMAND-OUTCOME.
ACTIVITY restricts selection to windows with an alert. OBSERVE supplies the
newly captured active link through OUTCOME-VALUE, or records an observation
failure separately. Signals STALE-TARGET or an operational condition.

[Source](../src/selection.lisp)

<a id="open-client-function"></a>

### open-client

`(open-client &key (program "tmux") socket-name socket-path config-file (timeout 30) (output-limit (* 16 1024 1024)))`

Open an SBCL/Linux subprocess client and check its tmux version.
PROGRAM must resolve to a native x86_64 ELF tmux executable.
SOCKET-NAME and SOCKET-PATH are mutually exclusive; omission selects tmux's
default socket. No daemon is started. TIMEOUT is seconds; OUTPUT-LIMIT bounds
combined stdout/stderr bytes per command. Signals an operational condition on
version/launch failure. Returned configuration strings are owned by the client.

[Source](../src/client.lisp)

<a id="outcome-arguments-function"></a>

### outcome-arguments

`(outcome-arguments outcome)`

Return an owned vector of the effective argv strings. No external I/O.

[Source](../src/transport.lisp)

<a id="outcome-cleanup-failures-function"></a>

### outcome-cleanup-failures

`(outcome-cleanup-failures outcome)`

Return a fresh vector of conditions encountered while releasing the process.

[Source](../src/transport.lisp)

<a id="outcome-elapsed-function"></a>

### outcome-elapsed

`(outcome-elapsed outcome)`

Return elapsed monotonic seconds for this retained result. No I/O.
Raw RUN-COMMAND measures its subprocess operation. Named operations include
preflight, dispatch and follow-up acquisition in their retained outcome timing.

[Source](../src/transport.lisp)

Applicable first argument types: [command-outcome](#command-outcome-type).

<a id="outcome-exit-code-function"></a>

### outcome-exit-code

`(outcome-exit-code outcome)`

Return the subprocess's integer exit status, or NIL if unknown. No I/O.

[Source](../src/transport.lisp)

Applicable first argument types: [command-outcome](#command-outcome-type).

<a id="outcome-observation-error-function"></a>

### outcome-observation-error

`(outcome-observation-error outcome)`

Return the condition from follow-up acquisition, or NIL. No I/O.
A successful mutation remains :SUCCEEDED when its replacement observation
fails. Do not repeat the mutation merely to obtain a replacement observation.

[Source](../src/transport.lisp)

Applicable first argument types: [command-outcome](#command-outcome-type).

<a id="outcome-phase-function"></a>

### outcome-phase

`(outcome-phase outcome)`

Return retained dispatch evidence, without I/O.
Raw process phases are :PREPARED, :LAUNCHING, :DISPATCHED and :EXITED. Named
operations may also report :PREFLIGHT or :GUARD-REJECTED before payload dispatch.
Phase is separate from OUTCOME-STATUS; an exited queue can have partially
completed effects even when it reported failure.

[Source](../src/transport.lisp)

Applicable first argument types: [command-outcome](#command-outcome-type).

<a id="outcome-reason-function"></a>

### outcome-reason

`(outcome-reason outcome)`

Return the retained failure reason keyword, or NIL. No I/O.
Examples include :DEADLINE and :CANCELLED; inspect the condition and phase too.

[Source](../src/transport.lisp)

Applicable first argument types: [command-outcome](#command-outcome-type).

<a id="outcome-status-function"></a>

### outcome-status

`(outcome-status outcome)`

Return :SUCCEEDED, :FAILED, :UNKNOWN or :NOT-DISPATCHED. No I/O.
These describe retained evidence, not rollback. Observation failure is separate
from mutation success; inspect OUTCOME-OBSERVATION-ERROR and OUTCOME-VALUE.

[Source](../src/transport.lisp)

Applicable first argument types: [command-outcome](#command-outcome-type).

<a id="outcome-stderr-function"></a>

### outcome-stderr

`(outcome-stderr outcome)`

Return a fresh octet vector containing retained diagnostic output.

[Source](../src/transport.lisp)

<a id="outcome-stdout-function"></a>

### outcome-stdout

`(outcome-stdout outcome)`

Return a fresh octet vector containing retained standard output.

[Source](../src/transport.lisp)

<a id="outcome-value-function"></a>

### outcome-value

`(outcome-value outcome)`

Return the resulting value and presence as two values, without I/O.
Copy data containers and strings; captured entity observations may be shared.

[Source](../src/transport.lisp)

<a id="panes-function"></a>

### panes

`(panes observation)`

Return a fresh vector of captured physical panes, without I/O.
Snapshots preserve first occurrence; windows preserve the captured pane order.

[Source](../src/model.lisp)

Applicable first argument types: [snapshot](#snapshot-type), [window](#window-type).

<a id="paste-buffer-function"></a>

### paste-buffer

`(paste-buffer client pane &key name separator raw bracketed verbatim delete cancel-token timeout output-limit)`

Paste a named or top buffer into PANE; return a COMMAND-OUTCOME.
Newlines become Return by default. RAW preserves newlines; SEPARATOR explicitly
replaces each newline with literal text and is mutually exclusive with RAW.
VERBATIM preserves every byte, implies RAW and disables tmux's newer control-byte
sanitization; it cannot be combined with a separator or bracket markers.
BRACKETED uses bracketed paste when the pane enabled it. DELETE removes the
selected buffer afterward. Tmux may accept without sending when input is
disabled; success does not prove application consumption. Signals STALE-TARGET
or an operational condition.

[Source](../src/buffers.lisp)

<a id="pipe-pane-function"></a>

### pipe-pane

`(pipe-pane client pane &key shell-command format-p (direction :output) toggle cancel-token timeout output-limit)`

Configure PANE's tmux-owned pipe and return a COMMAND-OUTCOME.
SHELL-COMMAND is shell source, literal to tmux by default; FORMAT-P explicitly
enables tmux format and time expansion before shell execution. DIRECTION is
:OUTPUT (pane to shell), :INPUT (shell to pane), or :BOTH. Omit SHELL-COMMAND,
or pass an empty string, to close the pipe. TOGGLE closes an existing pipe
without starting its replacement. Replacing a pipe closes the previous one.
Completion acknowledges configuration, not shell startup, success or output
consumption. The daemon owns the pipe child; closing CLIENT leaves it running.
Literal commands exceeding tmux's time-format capacity fail before I/O.
Signals STALE-TARGET or an operational condition; never retries configuration.

[Source](../src/process-operations.lisp)

<a id="previous-layout-function"></a>

### previous-layout

`(previous-layout client window &key (observe t) cancel-token timeout output-limit)`

Cycle WINDOW to tmux's previous layout; return an outcome and optional replacement.
Unzooms the window. Captured values remain unchanged. Signals STALE-TARGET or
an operational condition; follow-up acquisition failure is retained separately.

[Source](../src/geometry.lisp)

<a id="previous-window-function"></a>

### previous-window

`(previous-window client session &key activity (observe t) cancel-token timeout output-limit)`

Select SESSION's previous window link; return a COMMAND-OUTCOME.
ACTIVITY restricts selection to windows with an alert. OBSERVE supplies the
newly captured active link through OUTCOME-VALUE, or records an observation
failure separately. Signals STALE-TARGET or an operational condition.

[Source](../src/selection.lisp)

<a id="provenance-function"></a>

### provenance

`(provenance observation)`

Return fresh captured provenance and acquisition bounds, without I/O.

[Source](../src/model.lisp)

Applicable first argument types: [entity](#entity-type), [snapshot](#snapshot-type).

<a id="refresh-function"></a>

### refresh

`(refresh client observation &rest options)`

Acquire a replacement observation, leaving the earlier capture unchanged.
CLIENT must own the original context/generation. Missing or replaced targets
signal STALE-TARGET. Attached-client refresh requires one unique live target
name with the same PID/creation/tty fingerprint; its observation identity changes.

[Source](../src/capture.lisp)

<a id="rename-session-function"></a>

### rename-session

`(rename-session client session text &key format-p (observe t) cancel-token timeout output-limit)`

Rename SESSION with literal TEXT, or an explicit FORMAT-P expression.
Return a COMMAND-OUTCOME. OBSERVE defaults true and supplies a replacement
through OUTCOME-VALUE; observation failure is retained separately. Tmux enforces
session-name restrictions and uniqueness. Signals STALE-TARGET or an operational
condition. Timeout and byte limits cover preflight, mutation and observation.

[Source](../src/operations.lisp)

<a id="rename-window-function"></a>

### rename-window

`(rename-window client window text &key format-p (observe t) cancel-token timeout output-limit)`

Rename the selected physical WINDOW and return a COMMAND-OUTCOME.
TEXT is literal by default; FORMAT-P explicitly enables tmux format expansion.
Tmux may normalize or reject names. OBSERVE acquires a replacement in
OUTCOME-VALUE; a failed follow-up stays in OUTCOME-OBSERVATION-ERROR without
erasing successful mutation. Earlier observations are unchanged. Signals
STALE-TARGET or an operational condition. Never retries the mutation.

[Source](../src/operations.lisp)

<a id="resize-pane-function"></a>

### resize-pane

`(resize-pane client pane &key width height direction (amount 1 amount-p) zoom (observe t) cancel-token timeout output-limit)`

Resize PANE and return a COMMAND-OUTCOME with an optional replacement pane.
Choose cell WIDTH/HEIGHT (1..10000), a DIRECTION and positive AMOUNT, or ZOOM.
DIRECTION is :LEFT, :RIGHT, :UP or :DOWN; AMOUNT defaults to one. ZOOM toggles
the window's zoom state. Modes are exclusive. Tmux may clamp sizes to the
available layout; inspect the observed value. Earlier captures stay unchanged.
Signals INVALID-ARGUMENT, STALE-TARGET or an operational condition.

[Source](../src/geometry.lisp)

<a id="resize-window-function"></a>

### resize-window

`(resize-window client window &key width height direction (amount 1 amount-p) fit (observe t) cancel-token timeout output-limit)`

Resize physical WINDOW and return an outcome with an optional replacement.
Choose cell WIDTH/HEIGHT (1..10000), a DIRECTION and positive AMOUNT, or FIT
(:SMALLEST or :LARGEST attached client). Modes are exclusive; dimensions are
subject to tmux's layout constraints. A resize sets the window-size option to
manual, as tmux does. Signals INVALID-ARGUMENT, STALE-TARGET or an operational
condition. Observation failure is retained separately from mutation success.

[Source](../src/geometry.lisp)

<a id="respawn-pane-function"></a>

### respawn-pane

`(respawn-pane client pane &key kill cwd environment (observe t) (command nil command-p) (shell-command nil shell-command-p) cancel-token timeout output-limit)`

Restart PANE's process and return a COMMAND-OUTCOME.
KILL explicitly replaces a running process; otherwise tmux requires it to have
exited. Omit COMMAND and SHELL-COMMAND to reuse the previous command. Explicit
argv, shell text, literal CWD and ENVIRONMENT follow NEW-WINDOW. OBSERVE returns
a replacement pane through OUTCOME-VALUE; its earlier capture stays unchanged.
The process may exit before observation. Signals STALE-TARGET or an operational
condition; never retries an uncertain restart.

[Source](../src/process-operations.lisp)

<a id="respawn-window-function"></a>

### respawn-window

`(respawn-window client window &key kill cwd environment (observe t) (command nil command-p) (shell-command nil shell-command-p) cancel-token timeout output-limit)`

Restart WINDOW as one pane and return a COMMAND-OUTCOME.
KILL explicitly replaces running processes. Tmux retains its first pane and
destroys every other pane in the physical window, including through other links.
Other options follow RESPAWN-PANE. OBSERVE supplies a replacement window without
changing earlier observations. Linked-window session context is selected by tmux.
Signals STALE-TARGET or an operational condition; never retries the restart.

[Source](../src/process-operations.lisp)

<a id="rotate-window-function"></a>

### rotate-window

`(rotate-window client window &key (direction :up) preserve-zoom (observe t) cancel-token timeout output-limit)`

Rotate WINDOW's pane positions :UP or :DOWN; return an outcome and replacement.
Tmux also advances the active pane. PRESERVE-ZOOM restores zoom after rotating.
Signals INVALID-ARGUMENT, STALE-TARGET or an operational condition. Captured
pane order remains unchanged in earlier observations.

[Source](../src/placement.lisp)

<a id="run-command-function"></a>

### run-command

`(run-command client arguments &key effect input cancel-token (timeout (slot-value client (quote timeout))) (output-limit (slot-value client (quote output-limit))))`

Execute explicit tmux argv and return a retained COMMAND-OUTCOME.
EFFECT must be :READ or :MUTATION. Arguments are literal argv strings; tmux's
own command/format grammar still applies. INPUT is an octet vector or NIL.
This escape hatch does not validate captured target identities. Failures signal
conditions retaining the outcome; uncertain mutations are never retried.

[Source](../src/client.lisp)

<a id="same-entity-p-function"></a>

### same-entity-p

`(same-entity-p left right)`

Compare captured identity, not captured field values. No I/O.
Context and generation must agree. Link comparison retains its expected window
and index. Attached clients compare equal only within their original capture.

[Source](../src/model.lisp)

<a id="save-buffer-function"></a>

### save-buffer

`(save-buffer client path &key name append cancel-token timeout output-limit)`

Save a named or top buffer's bytes to literal PATH; return a COMMAND-OUTCOME.
Overwrite the file unless APPEND is true. Relative paths follow tmux's command
client cwd. Use SHOW-BUFFER for returned bytes. Success records tmux's reported
completion, not independently verified file contents or durability. In particular,
tmux 3.3a can suppress file-write errors. An uncertain write is never retried.
Signals INVALID-ARGUMENT or an operational condition.

[Source](../src/buffers.lisp)

<a id="select-layout-function"></a>

### select-layout

`(select-layout client window layout &key (observe t) cancel-token timeout output-limit)`

Apply LAYOUT to physical WINDOW; return an outcome and optional replacement.
LAYOUT is :EVEN-HORIZONTAL, :EVEN-VERTICAL, :MAIN-HORIZONTAL, :MAIN-VERTICAL,
:TILED, or (:CUSTOM string) containing a tmux layout description. Custom text
is literal and tmux validates its checksum and geometry. This unzooms the
window. Signals INVALID-ARGUMENT, STALE-TARGET or an operational condition.

[Source](../src/geometry.lisp)

<a id="select-pane-function"></a>

### select-pane

`(select-pane client pane &key (observe t) cancel-token timeout output-limit)`

Select PANE within its physical window; return a COMMAND-OUTCOME.
OBSERVE supplies a replacement pane through OUTCOME-VALUE. Captured getters
stay local and unchanged. Signals STALE-TARGET or an operational condition.

[Source](../src/operations.lisp)

<a id="select-window-function"></a>

### select-window

`(select-window client link &key (observe t) cancel-token timeout output-limit)`

Select a captured window LINK within its session; return a COMMAND-OUTCOME.
The expected session/index/window mapping is checked before dispatch. OBSERVE
supplies a replacement link through OUTCOME-VALUE. A moved or replaced mapping
signals STALE-TARGET; external failures retain their command outcome.

[Source](../src/operations.lisp)

<a id="send-keys-function"></a>

### send-keys

`(send-keys client pane keys &key (repeat 1) cancel-token timeout output-limit)`

Send a finite nonempty list/vector of tmux key strings to PANE.
Return a COMMAND-OUTCOME. REPEAT is a positive count. Tmux interprets key names
such as C-c and Enter; its unrecognized strings fall back to literal input.
Use SEND-TEXT when key-name interpretation must be disabled. Acknowledgment
does not prove application readiness or consumption.

[Source](../src/terminal-operations.lisp)

<a id="send-prefix-function"></a>

### send-prefix

`(send-prefix client pane &key second cancel-token timeout output-limit)`

Send the session's configured prefix key to PANE; return a COMMAND-OUTCOME.
SECOND selects prefix2. Tmux's active pane mode handles input; completion does
not establish application consumption. Signals STALE-TARGET or an operational
condition retaining its outcome.

[Source](../src/terminal-operations.lisp)

<a id="send-text-function"></a>

### send-text

`(send-text client pane text &key enter cancel-token timeout output-limit)`

Send literal TEXT to PANE through tmux and return a COMMAND-OUTCOME.
ENTER appends one Return key in the same command. Text such as C-c remains
literal text; it is not parsed as a key name, tmux format or shell command.
Tmux's active pane mode still handles the resulting input. Completion means
tmux processed the send request, not that the application consumed it. An
oversized encoded command is rejected without silently splitting the input.

[Source](../src/terminal-operations.lisp)

<a id="session-function"></a>

### session

`(session entity)`

Return the locally captured session of a link or attached client.

[Source](../src/model.lisp)

Applicable first argument types: [attached-client](#attached-client-type), [window-link](#window-link-type).

<a id="sessions-function"></a>

### sessions

`(sessions snapshot)`

Return a fresh vector of physical sessions in captured wire order. No I/O.

[Source](../src/model.lisp)

Applicable first argument types: [snapshot](#snapshot-type).

<a id="set-buffer-function"></a>

### set-buffer

`(set-buffer client data &key name append cancel-token timeout output-limit)`

Store literal DATA in a named or automatic buffer; return a COMMAND-OUTCOME.
DATA is a NUL-free string or an octet vector. Strings use tmux set-buffer;
octets use its load-buffer stdin path and preserve NUL and invalid UTF-8.
APPEND is available only for strings. Empty DATA is tmux's no-op and preserves
an existing buffer. NAME is literal; omission creates an automatic name.
New names reject backslashes, ASCII controls and DEL before I/O because tmux
versions otherwise rewrite or reject them. Spaces and Unicode are supported.
Signals INVALID-ARGUMENT or an operational condition.

[Source](../src/buffers.lisp)

<a id="show-buffer-function"></a>

### show-buffer

`(show-buffer client &key name cancel-token timeout output-limit)`

Read a literal named buffer, or tmux's top buffer; return octets and an outcome.
Output is an owned octet vector with no text decoding or trimming. Uses an
ordinary unattached tmux client and requires normal completion with empty stderr.
Names select the buffer at dispatch, not an earlier incarnation. A post-launch
failure does not prove non-dispatch. Signals an operational condition retaining
its outcome and any partial bytes.

[Source](../src/buffers.lisp)

<a id="split-pane-function"></a>

### split-pane

`(split-pane client pane &key (direction :vertical) size percent before full-size cwd environment (detached t) (command nil command-p) (shell-command nil shell-command-p) cancel-token timeout output-limit)`

Split captured PANE and return a COMMAND-OUTCOME with the created pane.
DIRECTION is :HORIZONTAL (left/right) or :VERTICAL (top/bottom). SIZE is a
positive cell count; PERCENT is 1 through 100, mutually exclusive with SIZE.
BEFORE places the pane before its target; FULL-SIZE spans the whole window.
DETACHED defaults true. CWD, ENVIRONMENT, COMMAND and SHELL-COMMAND follow
NEW-WINDOW. Failed acquisition after successful creation is retained separately.
Signals STALE-TARGET or an operational condition; never retries the mutation.

[Source](../src/creation.lisp)

<a id="swap-panes-function"></a>

### swap-panes

`(swap-panes client first-pane second-pane &key (detached t) preserve-zoom (observe t) cancel-token timeout output-limit)`

Swap two physical panes; return an outcome with replacements in a fresh vector.
The vector follows argument order. DETACHED defaults true; tmux still adjusts
active-pane references when panes change windows. PRESERVE-ZOOM restores zoom.
Signals STALE-TARGET or an operational condition. Earlier captures stay local
and unchanged; observation failure is retained separately.

[Source](../src/placement.lisp)

<a id="swap-windows-function"></a>

### swap-windows

`(swap-windows client first-link second-link &key select (observe t) cancel-token timeout output-limit)`

Swap physical windows at two captured links; return a COMMAND-OUTCOME.
OBSERVE supplies a fresh vector of replacement links in argument order. SELECT
selects the affected indexes in their sessions; omission keeps current indexes.
Tmux group restrictions apply. Signals STALE-TARGET or an operational condition;
old links retain their original expected window IDs.

[Source](../src/placement.lisp)

<a id="title-function"></a>

### title

`(title entity)`

Return a copied captured pane title and presence; empty is present. No I/O.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type).

<a id="tmux-version-function"></a>

### tmux-version

`(tmux-version client)`

Return a fresh copy of the release string observed when CLIENT opened.

[Source](../src/client.lisp)

<a id="unlink-window-function"></a>

### unlink-window

`(unlink-window client link &key kill-if-last cancel-token timeout output-limit)`

Remove the captured LINK and return a COMMAND-OUTCOME without a value.
Tmux refuses the last reference unless KILL-IF-LAST is explicit; group membership
affects that check. Removing a last link can destroy its window and session.
Signals STALE-TARGET or an operational condition. Does not refresh a deleted link.

[Source](../src/placement.lisp)

<a id="width-function"></a>

### width

`(width entity)`

Return the positive captured width and presence, without I/O.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type), [window](#window-type).

<a id="window-function"></a>

### window

`(window entity)`

Return the locally captured physical window of a pane or link.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type), [window-link](#window-link-type).

<a id="window-links-function"></a>

### window-links

`(window-links observation)`

Return every captured window link in wire order as a fresh vector. No I/O.

[Source](../src/model.lisp)

Applicable first argument types: [session](#session-type), [snapshot](#snapshot-type), [window](#window-type).

<a id="windows-function"></a>

### windows

`(windows observation)`

Return a fresh vector of captured windows, without I/O.
Snapshot windows are physical entities in first-occurrence order. Session
windows contain one item per link and preserve repeated physical windows.

[Source](../src/model.lisp)

Applicable first argument types: [session](#session-type), [snapshot](#snapshot-type).

<a id="with-client-function"></a>

### with-client

`(with-client (name &rest options) &body body)`

Bind NAME to a client and close the original resource on every exit.
Body declarations and multiple values are preserved. Cleanup failure signals
after normal return; during unwind it is retained in CLIENT-CLEANUP-FAILURES.

[Source](../src/client.lisp)

## Classes and conditions

These types are acquired or signalled by the library; their slots are private.

<a id="attached-client-type"></a>

### attached-client

One captured attached-tmux-client row; identity is observation-scoped.

[Source](../src/model.lisp)

Direct supertypes: [entity](#entity-type).

<a id="cancellation-token-type"></a>

### cancellation-token

One-way cancellation state; idle tokens own no OS descriptors.

[Source](../src/transport.lisp)

Direct supertypes: `standard-object`.

<a id="cleanup-failed-type"></a>

### cleanup-failed

Owned resources could not be released within the cleanup bound.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="client-type"></a>

### client

A connection scope with one external-operation lease.
Closing cancels owned work and leaves the tmux daemon alive. Captured data may
outlive the client. Public operations never expose its mutable storage.

[Source](../src/client.lisp)

Direct supertypes: `standard-object`.

<a id="client-busy-type"></a>

### client-busy

Another external operation already owns the client's lease.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="client-closed-type"></a>

### client-closed

An external operation was attempted on a closing/closed client.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="command-cancelled-type"></a>

### command-cancelled

Cancellation stopped an operation; inspect dispatch phase.

[Source](../src/conditions.lisp)

Direct supertypes: [outcome-unknown](#outcome-unknown-type).

<a id="command-failed-type"></a>

### command-failed

The command failed; ERROR-OUTCOME retains diagnostics.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="command-outcome-type"></a>

### command-outcome

A retained command result; byte and argument readers copy storage.
STATUS is :SUCCEEDED, :FAILED, :UNKNOWN or :NOT-DISPATCHED. PHASE is separate
dispatch evidence. An observation error does not erase a successful mutation.

[Source](../src/transport.lisp)

Direct supertypes: `standard-object`.

<a id="deadline-exceeded-type"></a>

### deadline-exceeded

The command exceeded its absolute deadline.

[Source](../src/conditions.lisp)

Direct supertypes: [outcome-unknown](#outcome-unknown-type).

<a id="decoding-error-type"></a>

### decoding-error

Captured bytes do not satisfy the expected text/record codec.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="entity-type"></a>

### entity

An owned observation from one snapshot; construct through acquisition.
Private slot mutation is unsupported. Refresh returns another observation.

[Source](../src/model.lisp)

Direct supertypes: `standard-object`.

<a id="field-unavailable-type"></a>

### field-unavailable

The field is unregistered for this model or its relation is unloaded.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="incomplete-snapshot-type"></a>

### incomplete-snapshot

Captured rows contradict each other or lack required references.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="invalid-argument-type"></a>

### invalid-argument

An argument violates the operation's declared contract.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="libtmux-error-type"></a>

### libtmux-error

A library failure with a message, original cause and outcome.

[Source](../src/conditions.lisp)

Direct supertypes: `error`.

<a id="outcome-unknown-type"></a>

### outcome-unknown

A dispatched operation did not establish its final outcome.

[Source](../src/conditions.lisp)

Direct supertypes: [command-failed](#command-failed-type).

<a id="output-limit-exceeded-type"></a>

### output-limit-exceeded

Combined stdout/stderr exceeded the configured byte limit.

[Source](../src/conditions.lisp)

Direct supertypes: [outcome-unknown](#outcome-unknown-type).

<a id="pane-type"></a>

### pane

A physical pane belonging to one captured window.

[Source](../src/model.lisp)

Direct supertypes: [entity](#entity-type).

<a id="session-type"></a>

### session

A captured physical tmux session.

[Source](../src/model.lisp)

Direct supertypes: [entity](#entity-type).

<a id="snapshot-type"></a>

### snapshot

A finite captured graph assembled over a recorded acquisition interval.
It contains owned observations, not a transactional view of a changing daemon.
Public accessors are local and return fresh mutable values.

[Source](../src/model.lisp)

Direct supertypes: `standard-object`.

<a id="stale-target-type"></a>

### stale-target

Captured target authority no longer agrees with the live server.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="unsupported-capability-type"></a>

### unsupported-capability

The live daemon does not support the requested operation contract.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="unsupported-configuration-type"></a>

### unsupported-configuration

Daemon configuration overrides a required built-in command contract.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="unsupported-platform-type"></a>

### unsupported-platform

The process backend lacks a required operating-system facility.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="unsupported-tmux-type"></a>

### unsupported-tmux

The selected tmux does not meet the supported version floor.

[Source](../src/conditions.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

<a id="window-type"></a>

### window

A physical window shared by zero or more captured links.

[Source](../src/model.lisp)

Direct supertypes: [entity](#entity-type).

<a id="window-link-type"></a>

### window-link

A captured session/index locator with its expected physical window ID.

[Source](../src/model.lisp)

Direct supertypes: [entity](#entity-type).
