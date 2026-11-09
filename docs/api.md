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
START-DAEMON/WITH-DAEMON separately own a new empty-config foreground daemon;
STOP-DAEMON releases that owner, with incomplete cleanup retained for retry.
See docs/index.md for the tutorial, API reference and current capability limits.

## Functions and macros

**Connect and manage lifetime**

[client-cleanup-failures](#client-cleanup-failures-function)
[client-open-p](#client-open-p-function)
[close-client](#close-client-function)
[open-client](#open-client-function)
[run-command](#run-command-function)
[tmux-version](#tmux-version-function)
[with-client](#with-client-function)

**Start and stop owned daemons**

[daemon-cleanup-failures](#daemon-cleanup-failures-function)
[daemon-failure](#daemon-failure-function)
[daemon-program](#daemon-program-function)
[daemon-socket-path](#daemon-socket-path-function)
[daemon-state](#daemon-state-function)
[error-daemon](#error-daemon-function)
[pending-daemon-cleanups](#pending-daemon-cleanups-function)
[start-daemon](#start-daemon-function)
[stop-daemon](#stop-daemon-function)
[with-daemon](#with-daemon-function)

**Acquire, traverse and project captured graphs**

[active-p](#active-p-function)
[clients](#clients-function)
[current-command](#current-command-function)
[current-path](#current-path-function)
[dead-p](#dead-p-function)
[entity-data](#entity-data-function)
[entity-model](#entity-model-function)
[fetch-clients](#fetch-clients-function)
[fetch-panes](#fetch-panes-function)
[fetch-sessions](#fetch-sessions-function)
[fetch-snapshot](#fetch-snapshot-function)
[fetch-windows](#fetch-windows-function)
[field-value](#field-value-function)
[height](#height-function)
[id](#id-function)
[index](#index-function)
[name](#name-function)
[panes](#panes-function)
[provenance](#provenance-function)
[refresh](#refresh-function)
[same-entity-p](#same-entity-p-function)
[session](#session-function)
[sessions](#sessions-function)
[title](#title-function)
[width](#width-function)
[window](#window-function)
[window-links](#window-links-function)
[windows](#windows-function)

**Inspect outcomes and cancel work**

[cancel](#cancel-function)
[cancelled-p](#cancelled-p-function)
[make-cancellation-token](#make-cancellation-token-function)
[outcome-arguments](#outcome-arguments-function)
[outcome-cleanup-failures](#outcome-cleanup-failures-function)
[outcome-elapsed](#outcome-elapsed-function)
[outcome-exit-code](#outcome-exit-code-function)
[outcome-observation-error](#outcome-observation-error-function)
[outcome-phase](#outcome-phase-function)
[outcome-reason](#outcome-reason-function)
[outcome-status](#outcome-status-function)
[outcome-stderr](#outcome-stderr-function)
[outcome-stdout](#outcome-stdout-function)
[outcome-value](#outcome-value-function)

**Create sessions, windows and panes**

[new-session](#new-session-function)
[new-window](#new-window-function)
[split-pane](#split-pane-function)

**Operate on attached terminal clients**

[detach-client](#detach-client-function)
[lock-client](#lock-client-function)
[refresh-client](#refresh-client-function)
[suspend-client](#suspend-client-function)
[switch-client](#switch-client-function)

**Coordinate server requests**

[display-message](#display-message-function)
[list-server-access](#list-server-access-function)
[lock-server](#lock-server-function)
[lock-session](#lock-session-function)
[server-access](#server-access-function)
[wait-for](#wait-for-function)

**Inspect commands and bind keys**

[bind-key](#bind-key-function)
[list-commands](#list-commands-function)
[list-keys](#list-keys-function)
[unbind-key](#unbind-key-function)

**Select, arrange and link targets**

[break-pane](#break-pane-function)
[join-pane](#join-pane-function)
[last-pane](#last-pane-function)
[last-window](#last-window-function)
[link-window](#link-window-function)
[move-pane](#move-pane-function)
[move-window](#move-window-function)
[next-layout](#next-layout-function)
[next-window](#next-window-function)
[previous-layout](#previous-layout-function)
[previous-window](#previous-window-function)
[resize-pane](#resize-pane-function)
[resize-window](#resize-window-function)
[rotate-window](#rotate-window-function)
[select-layout](#select-layout-function)
[select-pane](#select-pane-function)
[select-window](#select-window-function)
[swap-panes](#swap-panes-function)
[swap-windows](#swap-windows-function)
[unlink-window](#unlink-window-function)

**Rename, capture, send input and manage pane processes**

[capture-pane](#capture-pane-function)
[capture-pane-bytes](#capture-pane-bytes-function)
[clear-history](#clear-history-function)
[copy-mode](#copy-mode-function)
[pipe-pane](#pipe-pane-function)
[rename-session](#rename-session-function)
[rename-window](#rename-window-function)
[respawn-pane](#respawn-pane-function)
[respawn-window](#respawn-window-function)
[send-keys](#send-keys-function)
[send-prefix](#send-prefix-function)
[send-text](#send-text-function)

**Read and write buffers and files**

[delete-buffer](#delete-buffer-function)
[list-buffers](#list-buffers-function)
[load-buffer](#load-buffer-function)
[paste-buffer](#paste-buffer-function)
[save-buffer](#save-buffer-function)
[set-buffer](#set-buffer-function)
[show-buffer](#show-buffer-function)

**Inspect and configure options, hooks and environment**

[configuration-error-name](#configuration-error-name-function)
[configuration-error-scope](#configuration-error-scope-function)
[configuration-partial-records](#configuration-partial-records-function)
[configuration-read-outcomes](#configuration-read-outcomes-function)
[remove-environment](#remove-environment-function)
[set-environment](#set-environment-function)
[set-hook](#set-hook-function)
[set-option](#set-option-function)
[show-environment](#show-environment-function)
[show-environment-text](#show-environment-text-function)
[show-hooks](#show-hooks-function)
[show-hooks-text](#show-hooks-text-function)
[show-option](#show-option-function)
[show-options](#show-options-function)
[show-options-text](#show-options-text-function)
[unset-environment](#unset-environment-function)
[unset-hook](#unset-hook-function)
[unset-option](#unset-option-function)

**Terminate explicit targets**

[kill-pane](#kill-pane-function)
[kill-server](#kill-server-function)
[kill-session](#kill-session-function)
[kill-window](#kill-window-function)

**Inspect failure evidence**

[error-actual-version](#error-actual-version-function)
[error-cause](#error-cause-function)
[error-client](#error-client-function)
[error-commands](#error-commands-function)
[error-feature](#error-feature-function)
[error-field](#error-field-function)
[error-message](#error-message-function)
[error-model](#error-model-function)
[error-outcome](#error-outcome-function)
[error-required-version](#error-required-version-function)
[error-setting](#error-setting-function)
[error-target](#error-target-function)

<a id="active-p-function"></a>

### active-p

`(active-p entity)`

Return captured active state and presence, without I/O. False is NIL,T.

[Source](../src/model.lisp)

Applicable first argument types: [pane](#pane-type), [window-link](#window-link-type).

<a id="bind-key-function"></a>

### bind-key

`(bind-key client key &key (table "prefix") repeat note (command nil command-p) (command-source nil source-p) cancel-token timeout output-limit)`

Replace TABLE's KEY binding and return a COMMAND-OUTCOME.
TABLE defaults to prefix. KEY, TABLE and optional NOTE are literal strings.
REPEAT enables native key repetition. Supply exactly one of COMMAND argv or
COMMAND-SOURCE, explicit tmux parser source. COMMAND argv owns each argument
and preserves its token boundary; its first token must not contain =.

Tmux parses the binding immediately. Assignments/directives in COMMAND-SOURCE
can change daemon environment before a later parse error. Aliases expand during
binding in both forms and can also introduce parser side effects. Failure is
not rollback. Ordinary stored command nodes run later on a key event with its
native target context; this does not retain captured-handle authority.

Success acknowledges the binding and its hooks, not later key execution.
Blocks under shared preflight/dispatch limits, acquires no observation and
never retries. Native key/source errors and uncertain outcomes remain inspectable.

See also: [error-outcome](#error-outcome-function), [list-keys](#list-keys-function), [send-keys](#send-keys-function), [unbind-key](#unbind-key-function).

[Source](../src/key-bindings.lisp)

<a id="break-pane-function"></a>

### break-pane

`(break-pane client pane source-link session index &key name (detached t) (observe t) cancel-token timeout output-limit)`

Break PANE from SOURCE-LINK into SESSION's free INDEX; return an outcome.
SOURCE-LINK fixes the session context when breaking the window's only pane;
tmux moves that link instead of creating another physical window. NAME is
literal. DETACHED defaults true. OBSERVE supplies the destination window link.
On tmux 3.7, a new named window requires a following RENAME-WINDOW in the same
guarded request; its configured hooks can run. Failure can leave the pane moved.
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

<a id="configuration-error-name-function"></a>

### configuration-error-name

`(configuration-error-name condition)`

Return the owned active name at failure, or NIL before name resolution. No I/O.

See also: [configuration-error-scope](#configuration-error-scope-function), [configuration-read-failed](#configuration-read-failed-type).

[Source](../src/configuration-acquisition.lisp)

<a id="configuration-error-scope-function"></a>

### configuration-error-scope

`(configuration-error-scope condition)`

Return the active native table scope at acquisition failure. No I/O.
This may be an ancestor table used for inherited lookup.

See also: [configuration-error-name](#configuration-error-name-function), [configuration-read-failed](#configuration-read-failed-type).

[Source](../src/configuration-acquisition.lisp)

<a id="configuration-partial-records-function"></a>

### configuration-partial-records

`(configuration-partial-records condition)`

Return owned copies of records fully resolved before acquisition failed. No I/O.
Inspect CONFIGURATION-READ-OUTCOMES for valid individual observations from a
failing or incomplete name. No partial record proves a complete acquisition.

See also: [configuration-read-failed](#configuration-read-failed-type), [outcome-value](#outcome-value-function).

[Source](../src/configuration-acquisition.lisp)

<a id="configuration-read-outcomes-function"></a>

### configuration-read-outcomes

`(configuration-read-outcomes condition)`

Return a fresh vector of all retained read outcomes, in acquisition order.
Outcome objects retain identity. OUTCOME-VALUE exposes any valid decoded leaf
observation, independently of the native outcome's success status. Preflight
failures can have no selected read outcome. No I/O.

See also: [configuration-partial-records](#configuration-partial-records-function), [error-outcome](#error-outcome-function), [outcome-value](#outcome-value-function).

[Source](../src/configuration-acquisition.lisp)

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

<a id="daemon-cleanup-failures-function"></a>

### daemon-cleanup-failures

`(daemon-cleanup-failures daemon)`

Return a fresh vector of retained secondary cleanup conditions. No I/O.
Conditions are shared diagnostics, newest first, bounded to sixteen entries.

See also: [daemon-failure](#daemon-failure-function), [pending-daemon-cleanups](#pending-daemon-cleanups-function), [stop-daemon](#stop-daemon-function).

[Source](../src/daemon.lisp)

<a id="daemon-failure-function"></a>

### daemon-failure

`(daemon-failure daemon)`

Return DAEMON's retained primary failure condition, or NIL. No I/O.
This shared diagnostic can describe background failure after startup returned.

See also: [daemon-cleanup-failures](#daemon-cleanup-failures-function), [daemon-state](#daemon-state-function).

[Source](../src/daemon.lisp)

<a id="daemon-program-function"></a>

### daemon-program

`(daemon-program daemon)`

Return an owned copy of DAEMON's resolved tmux executable path. No I/O.
Pass it as OPEN-CLIENT's :PROGRAM when connecting through DAEMON-SOCKET-PATH.

See also: [daemon-socket-path](#daemon-socket-path-function), [open-client](#open-client-function).

[Source](../src/daemon.lisp)

<a id="daemon-socket-path-function"></a>

### daemon-socket-path

`(daemon-socket-path daemon)`

Return an owned copy of DAEMON's private socket path, or NIL before allocation.
No I/O. An ordinary client may connect while the owner is READY. Closing that
client leaves the daemon alive; STOP-DAEMON releases the daemon itself.

See also: [daemon-program](#daemon-program-function), [open-client](#open-client-function), [stop-daemon](#stop-daemon-function).

[Source](../src/daemon.lisp)

<a id="daemon-state-function"></a>

### daemon-state

`(daemon-state daemon)`

Return DAEMON's observed lifecycle state without I/O.
States are :STARTING, :READY, :STOPPING, :FAILED and :CLOSED. READY records
completed startup verification, not a promise of future process liveness.

See also: [daemon-failure](#daemon-failure-function), [stop-daemon](#stop-daemon-function).

[Source](../src/daemon.lisp)

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

<a id="detach-client-function"></a>

### detach-client

`(detach-client client target &key cancel-token timeout output-limit)`

Request detachment of captured terminal TARGET; return a COMMAND-OUTCOME.
CLIENT must own the observation. Success acknowledges the server's request,
not frontend process exit or terminal restoration. Returns no replacement.
Blocks under the supplied limits. The unique name/PID/creation/tty preflight
cannot exclude replacement between validation and dispatch. Missing or foreign
targets signal STALE-TARGET; external failures retain their outcome. Never
retries, detaches other clients, kills a parent, or starts a shell command.

See also: [fetch-clients](#fetch-clients-function), [outcome-status](#outcome-status-function), [switch-client](#switch-client-function).

[Source](../src/client-operations.lisp)

<a id="display-message-function"></a>

### display-message

`(display-message client message &key target format-p cancel-token timeout output-limit)`

Print MESSAGE through tmux; return owned UTF-8 text and a COMMAND-OUTCOME.
Always uses the ordinary -p printer, preserving its whitespace and trailing lines.
Native versions can escape output, so it is not a byte-identical echo. MESSAGE
is literal by default. FORMAT-P enables tmux format and time expansion;
#() may start shell jobs but does not wait for their output. Fresh requests can
print empty or incomplete job results. The native command client owns those
jobs; its disconnect cleans them up.

TARGET may be a captured session, window, pane or window-link owned by CLIENT.
Use a window-link for exact session/index context. With no target, tmux selects
the context; physical windows and panes also leave their session context to
tmux. Foreign, replaced or vanished targets signal STALE-TARGET.

The result includes after-hook printer output; it is not a decoded scalar or
configuration record. Hooks may also have effects. The call blocks under shared
preflight/dispatch limits, acquires no replacement and never retries. Tmux 3.3a
literal fallback limits the escaped intermediate text to 8,191 UTF-8 bytes;
newer daemons use native literal printing. Encoded command limits also apply.
Invalid UTF-8 signals DECODING-ERROR with its outcome; other failures retain
their diagnostic outcome. Local validation signals INVALID-ARGUMENT.

See also: [capture-pane](#capture-pane-function), [error-outcome](#error-outcome-function), [outcome-stdout](#outcome-stdout-function), [run-command](#run-command-function), [set-hook](#set-hook-function).

[Source](../src/server-operations.lisp)

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

<a id="error-daemon-function"></a>

### error-daemon

`(error-daemon condition)`

Return the daemon owner retained by a startup or cleanup failure.
The owner may need STOP-DAEMON even when START-DAEMON did not return. No I/O.

See also: [daemon-cleanup-failed](#daemon-cleanup-failed-type), [daemon-start-failed](#daemon-start-failed-type), [pending-daemon-cleanups](#pending-daemon-cleanups-function).

[Source](../src/daemon.lisp)

Applicable first argument types: [daemon-cleanup-failed](#daemon-cleanup-failed-type), [daemon-start-failed](#daemon-start-failed-type).

<a id="error-feature-function"></a>

### error-feature

`(error-feature condition)`

Return the unsupported capability's keyword identifier. No I/O.

[Source](../src/conditions.lisp)

Applicable first argument types: [unsupported-capability](#unsupported-capability-type), [unsupported-platform](#unsupported-platform-type).

<a id="error-field-function"></a>

### error-field

`(error-field condition)`

Return the requested field key, including an unregistered key. No I/O.
An invalid caller value is retained as supplied; it need not be a keyword.

[Source](../src/conditions.lisp)

Applicable first argument types: [field-unavailable](#field-unavailable-type), `invalid-filter`.

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

Applicable first argument types: [field-unavailable](#field-unavailable-type), `invalid-filter`, `invalid-query-target`.

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

Return the captured target associated with a dispatch refusal, or NIL. No I/O.

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
TIMEOUT controls one acquisition deadline and OUTPUT-LIMIT caps combined output,
including at most two retries after contradictory observations. Synchronous
setup and additional cleanup can extend caller wall time. ROW-LIMIT bounds each listing;
ENTITY-LIMIT bounds the complete graph; FIELD-LIMIT bounds encoded field bytes.
No daemon is started. A live daemon with zero sessions yields empty vectors;
connection/listing failures remain errors. Closing CLIENT leaves this snapshot
usable. This is an interval observation, not a transactional snapshot.

See also: [error-outcome](#error-outcome-function), [fetch-panes](#fetch-panes-function), [provenance](#provenance-function), [refresh](#refresh-function).

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

<a id="kill-pane-function"></a>

### kill-pane

`(kill-pane client pane &key cancel-token timeout output-limit)`

Delete exactly the captured physical PANE and return a COMMAND-OUTCOME.
The live pane identity is checked before dispatch. Other panes are preserved.
Signals STALE-TARGET when PANE disappeared or belongs to another generation.
Never retries the mutation.


See also: [kill-server](#kill-server-function), [kill-session](#kill-session-function), [kill-window](#kill-window-function).

[Source](../src/termination.lisp)

<a id="kill-server-function"></a>

### kill-server

`(kill-server client &key cancel-token timeout output-limit)`

Terminate CLIENT's preflight-accepted daemon and return a COMMAND-OUTCOME.
Success requires both a pre-dispatch receipt and observed exit of the server
process accepted during this call. Missing evidence signals OUTCOME-UNKNOWN;
cancellation or a deadline never causes an automatic retry. The connection
CLIENT stays open but its generation is invalidated after observed server death.
A failed exit wait retains :SERVER-EXIT-UNOBSERVED and the underlying
ERROR-CAUSE. CLOSE-CLIENT never calls this function.


See also: [close-client](#close-client-function), [kill-session](#kill-session-function), [outcome-phase](#outcome-phase-function), [outcome-status](#outcome-status-function).

[Source](../src/termination.lisp)

<a id="kill-session-function"></a>

### kill-session

`(kill-session client session &key cancel-token timeout output-limit)`

Delete exactly the captured SESSION and return a COMMAND-OUTCOME.
Tmux removes that session's links and panes no longer referenced elsewhere.
The live identity is checked before dispatch; the mutation is never retried.


See also: [kill-pane](#kill-pane-function), [kill-server](#kill-server-function), [kill-window](#kill-window-function).

[Source](../src/termination.lisp)

<a id="kill-window-function"></a>

### kill-window

`(kill-window client window &key cancel-token timeout output-limit)`

Delete exactly the captured physical WINDOW and return a COMMAND-OUTCOME.
Every link to that physical window is removed by tmux. Other windows remain.
The live identity is checked before dispatch; the mutation is never retried.


See also: [kill-pane](#kill-pane-function), [kill-server](#kill-server-function), [kill-session](#kill-session-function).

[Source](../src/termination.lisp)

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

<a id="list-commands-function"></a>

### list-commands

`(list-commands client &key command format cancel-token timeout output-limit)`

Inspect built-in tmux commands; return owned UTF-8 printer text and an outcome.
Omit COMMAND to list all built-ins. COMMAND is an exact name or built-in alias
through tmux 3.5a; unknown selectors produce no rows. From 3.6, unique prefixes
are accepted and unknown/ambiguous selectors fail. Configured command-alias
entries are not listed or expanded by this selector.

FORMAT is explicit tmux format source, without time expansion. #() can start
asynchronous jobs owned by this command client; results may be incomplete and
disconnect cleans up those jobs. Omission uses tmux's human-readable format.
Preserve native escaping, whitespace and after-hook output; this is not a
decoded registry.
Blocks under shared preflight/dispatch limits, never retries and starts no
daemon. Failures retain their outcome; invalid UTF-8 signals DECODING-ERROR.

See also: [display-message](#display-message-function), [error-outcome](#error-outcome-function), [list-keys](#list-keys-function), [outcome-stdout](#outcome-stdout-function).

[Source](../src/key-bindings.lisp)

<a id="list-keys-function"></a>

### list-keys

`(list-keys client &key table key format cancel-token timeout output-limit)`

Inspect key bindings; return owned UTF-8 printer text and a command outcome.
Omit TABLE to list every key table. TABLE and KEY are literal strings; native
unknown-table and invalid-key failures remain errors. An unbound valid KEY is
an error except on tmux 3.7 through 3.7c, which return empty text. Those releases
also send a single matching row to the server message log and any selected
frontend's status line instead of stdout. Empty text does not prove absence.
FORMAT is explicit tmux format source
and requires live tmux 3.7 or newer; older daemons signal UNSUPPORTED-CAPABILITY
before payload dispatch. Omission uses the native human-readable listing.

FORMAT has no time expansion. #() can start asynchronous command-client jobs,
whose output may be incomplete and whose cleanup follows client disconnect.
Empty expanded lines may be omitted. Native escaping, whitespace and after-hook
output are preserved; the text is not a parsed or replayable configuration.
Blocks under shared preflight/dispatch limits and never retries. Invalid UTF-8 signals
DECODING-ERROR; operational failures retain their outcome.

See also: [bind-key](#bind-key-function), [error-outcome](#error-outcome-function), [list-commands](#list-commands-function), [unbind-key](#unbind-key-function).

[Source](../src/key-bindings.lisp)

<a id="list-server-access-function"></a>

### list-server-access

`(list-server-access client &key cancel-token timeout output-limit)`

Print the daemon ACL; return owned UTF-8 text and a COMMAND-OUTCOME.
The ordinary native listing preserves escaping and whitespace. Before 3.8,
rows use (R)/(W); from 3.8 they include U/G account kinds. UID 0 is omitted and
unresolvable names print as unknown. An empty listing does not prove that no
account has access. This is printer output, not a decoded authorization model.
Blocks under shared preflight/dispatch limits and never retries or acquires an
observation. Invalid UTF-8 signals DECODING-ERROR; native and operational
failures retain their outcomes.

See also: [error-outcome](#error-outcome-function), [outcome-stdout](#outcome-stdout-function), [server-access](#server-access-function).

[Source](../src/server-operations.lisp)

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

<a id="lock-client-function"></a>

### lock-client

`(lock-client client target &key cancel-token timeout output-limit)`

Request locking of captured terminal TARGET; return a COMMAND-OUTCOME.
The frontend runs the session's configured lock-command through its shell.
Success acknowledges the request, not lock startup, completion or authentication.
An already suspended frontend or an empty/oversized lock command can be a no-op.
CLIENT must own TARGET.
Blocks under shared preflight/dispatch limits; returns no replacement. Stale or
foreign targets signal STALE-TARGET; other failures retain their outcome.
Preflight cannot exclude client replacement before dispatch. Never retries.

See also: [fetch-clients](#fetch-clients-function), [lock-server](#lock-server-function), [lock-session](#lock-session-function), [outcome-status](#outcome-status-function), [set-option](#set-option-function), [suspend-client](#suspend-client-function).

[Source](../src/client-operations.lisp)

<a id="lock-server-function"></a>

### lock-server

`(lock-server client &key cancel-token timeout output-limit)`

Request locking of all attached frontends on CLIENT's daemon.
Return a COMMAND-OUTCOME after guarded dispatch. Live frontend membership
determines the recipients; this is wider than one captured session. Each
frontend runs its configured lock-command. Control clients, suspended
frontends and empty/oversized commands are skipped. Success acknowledges
the request, not startup, completion or authentication. Blocks under shared
preflight/dispatch limits and returns no replacement. Failures retain their
outcome. Lock programs belong to the frontends; closing CLIENT leaves them
running. Never retries.

See also: [error-outcome](#error-outcome-function), [lock-client](#lock-client-function), [lock-session](#lock-session-function), [outcome-status](#outcome-status-function), [set-option](#set-option-function).

[Source](../src/server-operations.lisp)

<a id="lock-session-function"></a>

### lock-session

`(lock-session client session &key cancel-token timeout output-limit)`

Request locking of SESSION's attached frontends; return a COMMAND-OUTCOME.
CLIENT must own the captured SESSION. The live session membership determines
which frontends receive the request. Each runs its configured lock-command;
control clients, suspended frontends and empty/oversized commands are skipped.
Success acknowledges the request, not startup, completion or authentication.
Blocks under shared preflight/dispatch limits and returns no replacement.
Foreign or vanished sessions signal STALE-TARGET; other failures retain their
outcome. Lock programs belong to the frontends; closing CLIENT leaves them
running. Never retries.

See also: [error-outcome](#error-outcome-function), [lock-client](#lock-client-function), [lock-server](#lock-server-function), [outcome-status](#outcome-status-function), [set-option](#set-option-function).

[Source](../src/server-operations.lisp)

<a id="make-cancellation-token-function"></a>

### make-cancellation-token

`(make-cancellation-token)`

Create a token for one or more operations. CANCEL is idempotent.
Signals UNSUPPORTED-PLATFORM outside the qualified runtime profile.

See also: [cancel](#cancel-function), [cancelled-p](#cancelled-p-function), [open-client](#open-client-function).

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
Checks the runtime profile and required OS facilities before resolving PROGRAM.
An unsupported profile or facility signals UNSUPPORTED-PLATFORM; ERROR-FEATURE
identifies the requirement. PROGRAM must resolve to a native x86_64 ELF tmux
executable; pass the underlying binary when PATH selects a script or shim.
SOCKET-NAME and SOCKET-PATH are mutually exclusive; omission selects tmux's
default socket. No daemon is started. TIMEOUT is seconds; OUTPUT-LIMIT bounds
combined stdout/stderr bytes per command. Signals an operational condition on
version/launch failure. Returned configuration strings are owned by the client.

See also: [close-client](#close-client-function), [error-feature](#error-feature-function), [unsupported-platform](#unsupported-platform-type), [with-client](#with-client-function).

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
Explicit server termination reports :SERVER-TERMINATED only after retained
pidfd readiness proves exit. Phase is separate from OUTCOME-STATUS; an exited
queue can have partially completed effects even when it reported failure.

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

<a id="pending-daemon-cleanups-function"></a>

### pending-daemon-cleanups

`(pending-daemon-cleanups)`

Return a fresh vector of owners with incomplete cleanup, without daemon I/O.
The library retains them even when startup leaves through a nonlocal exit.
Successful STOP-DAEMON removes an owner from this collection.

See also: [error-daemon](#error-daemon-function), [stop-daemon](#stop-daemon-function).

[Source](../src/daemon.lisp)

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

<a id="refresh-client-function"></a>

### refresh-client

`(refresh-client client target &key status-only cancel-token timeout output-limit)`

Request a redraw of captured terminal TARGET; return a COMMAND-OUTCOME.
STATUS-ONLY requests only the status line; NIL requests the whole display.
Success acknowledges scheduling, not completed terminal rendering. This is an
external operation; REFRESH instead acquires a replacement observation.
CLIENT must own TARGET. Blocks under shared preflight/dispatch limits. A stale
or foreign target signals STALE-TARGET; other failures retain their outcome.
The client fingerprint is checked before dispatch, with a remaining replacement
race. Returns no replacement and never retries the request.

See also: [fetch-clients](#fetch-clients-function), [outcome-status](#outcome-status-function), [refresh](#refresh-function).

[Source](../src/client-operations.lisp)

<a id="remove-environment-function"></a>

### remove-environment

`(remove-environment client name &key scope target cancel-token timeout output-limit)`

Store tmux's removal marker for NAME and return its COMMAND-OUTCOME.
SCOPE/TARGET follow SET-ENVIRONMENT. A removal marker is distinct from absence
and from a present empty string. UNSET-ENVIRONMENT deletes the entry instead.
Never retries the mutation.

See also: [set-environment](#set-environment-function), [unset-environment](#unset-environment-function).

[Source](../src/configuration-operations.lisp)

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

<a id="server-access-function"></a>

### server-access

`(server-access client principal access &key group-p cancel-token timeout output-limit)`

Change PRINCIPAL's native daemon ACL entry; return a COMMAND-OUTCOME.
PRINCIPAL is a nonempty literal account name, resolved by the daemon's name
service, not a numeric UID/GID. GROUP-P selects a group and requires live tmux
3.8; older daemons signal UNSUPPORTED-CAPABILITY before payload dispatch.

ACCESS is :ALLOW (add a writable entry), :DENY (remove an entry), :READ-ONLY
or :READ-WRITE (update or add). Adding an existing entry and removing an absent
one are errors. Root and the daemon-owner UID cannot be changed. :DENY creates
no deny rule: from 3.8, a removed user can still match its peer GID's entry.
Explicit UID entries take precedence over that GID; supplementary groups are
not searched. Cross-user filesystem access must be configured separately.

From 3.8, removal and permission updates recompute every connected client's
read-only state. This can clear an unrelated frontend's separate read-only
flag when its effective ACL entry is writable. Updates can schedule client
disconnection; success does not prove frontend exit. Already scheduled exits
are not cancelled by a later grant.

Blocks under shared preflight/dispatch limits, acquires no observation and
never retries. Invalid input signals INVALID-ARGUMENT; native errors and
uncertain effects retain their outcome. Earlier captures stay unchanged.

See also: [error-outcome](#error-outcome-function), [fetch-clients](#fetch-clients-function), [list-server-access](#list-server-access-function), [refresh](#refresh-function).

[Source](../src/server-operations.lisp)

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

<a id="set-environment-function"></a>

### set-environment

`(set-environment client name value &key scope target format-p hidden cancel-token timeout output-limit)`

Set one raw tmux environment entry and return its COMMAND-OUTCOME.
SCOPE is required: :GLOBAL rejects TARGET; :SESSION requires a captured session.
NAME must match [A-Za-z_][A-Za-z0-9_]*. VALUE is literal unless FORMAT-P
explicitly requests tmux format expansion. HIDDEN sets tmux's hidden flag.
This mutates one raw table, not an effective merged child environment. Never
retries or refreshes captured observations. See UNSET-ENVIRONMENT for deletion
and REMOVE-ENVIRONMENT for an explicit tombstone.

See also: [remove-environment](#remove-environment-function), [unset-environment](#unset-environment-function).

[Source](../src/configuration-operations.lisp)

<a id="set-hook-function"></a>

### set-hook

`(set-hook client name command-source &key scope target (key nil key-p) append cancel-token timeout output-limit)`

Install tmux COMMAND-SOURCE for one registered hook and return an outcome.
SCOPE/TARGET follow SET-OPTION. COMMAND-SOURCE is explicit tmux command
language, not Lisp code; this function neither reads nor executes it locally.
KEY selects one hook-array entry. APPEND applies to an unkeyed hook assignment;
tmux does not append command source within a keyed hook entry. The ordinary
install path never uses set-hook -R, but tmux may still run a registered native
after-hook such as `after-set-hook` as a consequence of this set-hook command.
Dynamic @ event sources require a live catalog that supports them. SET-OPTION
rejects registered hooks; use UNSET-HOOK to remove this state. Never retries.

See also: [set-option](#set-option-function), [unset-hook](#unset-hook-function).

[Source](../src/configuration-operations.lisp)

<a id="set-option-function"></a>

### set-option

`(set-option client name value &key scope target (key nil key-p) format-p append only-if-unset cancel-token timeout output-limit)`

Set one typed tmux option and return its COMMAND-OUTCOME.
SCOPE is required and names one explicit table: :SERVER, :GLOBAL-SESSION,
:SESSION, :GLOBAL-WINDOW, :WINDOW or :PANE. Local scopes require a captured
TARGET of the matching type; global scopes reject one. NAME is resolved in the
exact live daemon catalog. Native numbers, Booleans and choices are validated
before payload dispatch. User names must match @[A-Za-z0-9_.-]+ and remain
strings. KEY addresses a registered array element. FORMAT-P treats VALUE as an
explicit tmux format; otherwise VALUE is literal and typed. APPEND is supported
for strings, keyed string-array elements and unkeyed array assignment. An
unkeyed array VALUE uses that option's native tmux list grammar; use KEY when
VALUE must remain one literal element. ONLY-IF-UNSET requests tmux -o: write
only when the option, or the selected array key, is absent from the local table.
Inherited values permit a local write; present false and empty values refuse
replacement. Refusal retains normal condition/outcome evidence through
ERROR-OUTCOME. The condition applies to this command; later commands and hooks
remain independent. Use UNSET-OPTION to remove state and SET-HOOK for registered
hooks. Never retries or acquires a replacement capture.

See also: [error-outcome](#error-outcome-function), [set-hook](#set-hook-function), [unset-option](#unset-option-function).

[Source](../src/configuration-operations.lisp)

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

<a id="show-environment-function"></a>

### show-environment

`(show-environment client &key scope target (names nil names-p) cancel-token timeout output-limit (record-limit 4096) (value-limit 1048576))`

Acquire named raw environment entries; return owned record/outcome vectors.
SCOPE is :GLOBAL or :SESSION; session scope requires a captured TARGET. NAMES
is required; explicit NIL/#() performs no I/O. Native names are nonempty UTF-8
without NUL or =, including names outside the mutation identifier grammar.
Each plist has :NAME, :SCOPE, :TARGET-ID, :VERSION, :STATE and :VALUE. States are
:PRESENT, :REMOVED and :ABSENT. Empty strings remain present. Present/removal
records additionally carry explicit :HIDDEN-P; absent records claim no visibility.
Read ordinary visibility first, then hidden only after empty success. Contradictory
views retry under the original limits. This is not a merged child environment.
Shared limits, ordinary-output assumptions and failure evidence follow SHOW-OPTIONS.

See also: [configuration-read-failed](#configuration-read-failed-type), [set-environment](#set-environment-function), [show-environment-text](#show-environment-text-function), [show-options](#show-options-function).

[Source](../src/configuration-acquisition.lisp)

<a id="show-environment-text-function"></a>

### show-environment-text

`(show-environment-text client &key scope target name hidden shell-format cancel-token timeout output-limit)`

Inspect a raw environment table; return owned UTF-8 text and a COMMAND-OUTCOME.
Required SCOPE is :GLOBAL or :SESSION; a session needs a captured TARGET.
NAME is literal nonempty text without NUL or =, including names outside the
mutation identifier grammar. Omission lists the table. HIDDEN selects hidden
entries; NIL selects ordinary entries. A visibility mismatch can return empty
text, which does not prove absence. Empty values, removal markers and native
escaping remain printer syntax. Session output is not a merged child environment.

SHELL-FORMAT selects native shell-looking presentation (-s); returned text is
never evaluated or executed. Ordinary hook output is preserved. This is not a
decoded environment mapping. Blocks under shared preflight/dispatch limits,
starts no daemon and never retries. Missing names remain errors; operational,
resource and UTF-8 failures retain client/outcome diagnostics.

See also: [error-outcome](#error-outcome-function), [remove-environment](#remove-environment-function), [set-environment](#set-environment-function), [show-options-text](#show-options-text-function).

[Source](../src/configuration-operations.lisp)

<a id="show-hooks-function"></a>

### show-hooks

`(show-hooks client &key scope target (names nil names-p) (include-inherited t) cancel-token timeout output-limit (record-limit 4096) (value-limit 1048576))`

Acquire owned hook records and native read outcomes, following SHOW-OPTIONS.
Omitted NAMES enumerates built-in hooks. Explicit dynamic @ names require a
supporting catalog and remain ordinary strings, without a registration claim.
Builtin command values are inert canonical tmux source. Inspection never requests
set-hook -R; ordinary after-read hooks still apply. :SERVER is unavailable.
No Lisp reader or evaluator parses source.

See also: [configuration-read-failed](#configuration-read-failed-type), [set-hook](#set-hook-function), [show-hooks-text](#show-hooks-text-function), [show-options](#show-options-function).

[Source](../src/configuration-acquisition.lisp)

<a id="show-hooks-text-function"></a>

### show-hooks-text

`(show-hooks-text client &key scope target name format monitors cancel-token timeout output-limit)`

Inspect native hooks; return owned UTF-8 printer text and a COMMAND-OUTCOME.
SCOPE/TARGET follow SET-HOOK; :SERVER is unavailable because show-hooks has no
server-table flag. NAME is a literal native reference; omission lists hooks.
Tmux can infer a built-in's table from NAME. A named ordinary @ option can
also be printed; that success does not prove event registration.

FORMAT is explicit tmux format source with no implicit time expansion.
MONITORS selects native monitor presentation (-B). Both require live tmux 3.8.
#() in FORMAT can start command-client jobs with incomplete results and cleanup
on disconnect. Native escaping, whitespace and ordinary hook output remain
printer text, not a decoded or replayable configuration. No -R is invoked.
Blocks under shared preflight/dispatch limits, starts no daemon and never
retries. Missing names and decoding/resource failures retain outcome evidence.

See also: [error-outcome](#error-outcome-function), [set-hook](#set-hook-function), [show-options-text](#show-options-text-function), [unset-hook](#unset-hook-function).

[Source](../src/configuration-operations.lisp)

<a id="show-option-function"></a>

### show-option

`(show-option client name &key scope target (key nil key-p) (include-inherited t) cancel-token timeout output-limit (record-limit 4096) (value-limit 1048576))`

Acquire one decoded option; return VALUE, PRESENT-P and a read-outcome vector.
False returns NIL,T; absence returns NIL,NIL. KEY selects an entry only after
acquiring a whole named array. A missing key does not fall through a present
local array. Mutable key text is copied before I/O and bounded to 1 MiB UTF-8.
Keys normalize under the exact live catalog before payload reads.
Scopes, limits, inheritance, ownership and failure evidence follow SHOW-OPTIONS.

See also: [configuration-read-failed](#configuration-read-failed-type), [outcome-value](#outcome-value-function), [show-options](#show-options-function).

[Source](../src/configuration-acquisition.lisp)

<a id="show-options-function"></a>

### show-options

`(show-options client &key scope target (names nil names-p) (include-inherited t) cancel-token timeout output-limit (record-limit 4096) (value-limit 1048576))`

Acquire decoded options; return owned record and native read-outcome vectors.
SCOPE and TARGET follow SET-OPTION. Omitted NAMES enumerates registered built-in
non-hook names in source order; explicit finite lists/vectors preserve requested
order and duplicates, including user names. At most 4096 names of at most 1 MiB
UTF-8 each are accepted, independently of RECORD-LIMIT. Explicit NIL/#() performs
no I/O after argument validation.
Each plist has :NAME, :SCOPE, :TARGET-ID, :VERSION, :TYPE, :ARRAY-P, :PRESENT-P,
:VALUE, :SOURCE-SCOPE, :SOURCE-TARGET-ID and :INHERITED-P. A present false flag
has NIL value and true presence. Arrays are vectors of (key-text . typed-value)
pairs, including sparse and supported string keys; empty arrays are present.
INCLUDE-INHERITED defaults true: use explicit ancestor tables only after local
absence and recheck every shadowing absence. Observations span an interval,
not a transaction. Read hooks can run again during bounded consistency retries.
One lease, token, deadline and aggregate byte/record budget covers all reads.
RECORD-LIMIT counts decoded rows/negative observations, including rechecks.
VALUE-LIMIT bounds each decoded UTF-8 value. Preparation and cleanup add wall time.
The ordinary printer must match its known schema; unrelated after-read output
signals a decoding failure. This assumes trusted native output, not per-leaf
origin authentication. Raw SHOW-OPTIONS-TEXT preserves unrestricted inspection.
Every requested name has a record even when absent. Read outcomes retain native
failures for expected missing names; this does not prove later hooks succeeded.
Records contain no operational handle; strings/containers own their storage.

See also: [configuration-read-failed](#configuration-read-failed-type), [show-hooks](#show-hooks-function), [show-option](#show-option-function), [show-options-text](#show-options-text-function).

[Source](../src/configuration-acquisition.lisp)

<a id="show-options-text-function"></a>

### show-options-text

`(show-options-text client &key scope target name include-inherited include-hooks value-only format cancel-token timeout output-limit)`

Inspect an option table; return owned UTF-8 printer text and a COMMAND-OUTCOME.
Required SCOPE and captured TARGET follow SET-OPTION. They select native flags;
tmux can infer a built-in's table from NAME instead. NAME is a literal option
reference with native abbreviation/array syntax; omission lists the table.
INCLUDE-INHERITED uses -A, which does not promise inherited user @ options in a
whole-table listing. INCLUDE-HOOKS uses -H and VALUE-ONLY uses -v.

FORMAT is explicit tmux format source, requires live tmux 3.8, and has no
implicit time expansion. #() can start asynchronous command-client jobs; their
results can be incomplete and disconnect cleans them up. Omission uses native
printer syntax. Escaping, whitespace and ordinary hook output remain text;
this does not decode values or prove presence, provenance or completeness.
Blocks under shared preflight/dispatch limits, starts no daemon and never
retries. Missing names remain errors with retained outcomes. Invalid UTF-8
signals DECODING-ERROR with the client and outcome.

See also: [error-outcome](#error-outcome-function), [set-option](#set-option-function), [show-environment-text](#show-environment-text-function), [show-hooks-text](#show-hooks-text-function).

[Source](../src/configuration-operations.lisp)

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

<a id="start-daemon-function"></a>

### start-daemon

`(start-daemon &key (program "tmux") (environment nil environment-p) working-directory temporary-directory (timeout 30) (output-limit 1048576) cancel-token)`

Start an owned empty-config daemon on a fresh private socket and await readiness.
Uses the qualified SBCL/Linux backend and explicit /dev/null configuration.
ENVIRONMENT is a finite list/vector of distinct NAME=VALUE strings; omission
copies the caller environment, and NIL selects an empty input environment.
Tmux selectors, socket activation and launcher controls are removed. Caller
locale is preserved; Bash shell metadata is not byte-transparent. Environment
values and the native executable remain trusted application configuration.
WORKING-DIRECTORY defaults to the captured current directory. The owner creates
a fresh directory under TEMPORARY-DIRECTORY (default UIOP's temporary directory).
Its canonical ancestors must be owned by this user or root; writable ancestors
must have the sticky bit. No existing daemon or endpoint is adopted.
TIMEOUT is one startup deadline after input preparation, including version and
readiness IPC. OUTPUT-LIMIT must be at least two bytes: half bounds daemon
lifetime diagnostics; the remainder bounds version/readiness output. Cleanup
adds bounded waits; synchronous setup and scheduling can extend caller wall time.
CANCEL-TOKEN affects startup only; after READY, STOP-DAEMON owns cancellation.
Signals DAEMON-START-FAILED with the original cause and owner on startup failure.

See also: [error-daemon](#error-daemon-function), [open-client](#open-client-function), [stop-daemon](#stop-daemon-function), [with-daemon](#with-daemon-function).

[Source](../src/daemon.lisp)

<a id="stop-daemon-function"></a>

### stop-daemon

`(stop-daemon daemon)`

Stop and reap DAEMON's owned child, then remove its checked socket and directory.
Idempotent after success; returns no values. Never targets a daemon through a
reusable PID or socket command. A 0.75-second admission wait and a separate
0.75-second worker join precede any retried job cleanup (up to 0.5 seconds).
Synchronous OS calls and scheduling can extend wall time. Failed cleanup signals
DAEMON-CLEANUP-FAILED and retains the owner for retry. Closing an ordinary client
does not call this function. Terminating the daemon does not establish exit of
every pane descendant.

See also: [daemon-cleanup-failures](#daemon-cleanup-failures-function), [pending-daemon-cleanups](#pending-daemon-cleanups-function), [with-daemon](#with-daemon-function).

[Source](../src/daemon.lisp)

<a id="suspend-client-function"></a>

### suspend-client

`(suspend-client client target &key cancel-token timeout output-limit)`

Request suspension of captured terminal TARGET; return a COMMAND-OUTCOME.
Tmux asks the frontend to stop with SIGTSTP. Success acknowledges the request;
it does not prove process suspension. An already suspended frontend can be a
no-op. Its controlling application owns resumption. CLIENT must own TARGET.
Blocks under shared preflight/dispatch limits; returns no replacement. Stale or
foreign targets signal STALE-TARGET; other failures retain their outcome.
Preflight cannot exclude client replacement before dispatch. Never retries.

See also: [detach-client](#detach-client-function), [fetch-clients](#fetch-clients-function), [lock-client](#lock-client-function), [outcome-status](#outcome-status-function).

[Source](../src/client-operations.lisp)

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

<a id="switch-client-function"></a>

### switch-client

`(switch-client client target session &key update-environment (observe t) cancel-token timeout output-limit)`

Switch captured terminal TARGET to SESSION and return a COMMAND-OUTCOME.
CLIENT is the connection owning both observations. UPDATE-ENVIRONMENT defaults
NIL, preserving the destination session environment; true applies tmux's
update-environment option using TARGET's environment. OBSERVE defaults true and
supplies a replacement attached-client through OUTCOME-VALUE. Earlier captures
stay unchanged; failed follow-up acquisition stays in OUTCOME-OBSERVATION-ERROR.
Blocks for preflight, dispatch and optional observation under shared limits.
Preflight checks the unique client name and PID/creation/tty fingerprint; tmux
does not atomically guard that fingerprint at dispatch. A changed or foreign
target signals STALE-TARGET. Operational failures retain their outcome; no
mutation is retried. Control clients are not supported by this operation.

See also: [detach-client](#detach-client-function), [fetch-clients](#fetch-clients-function), [outcome-value](#outcome-value-function), [refresh](#refresh-function).

[Source](../src/client-operations.lisp)

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

<a id="unbind-key-function"></a>

### unbind-key

`(unbind-key client key &key (table "prefix") cancel-token timeout output-limit)`

Remove exactly one KEY from TABLE and return a COMMAND-OUTCOME.
TABLE defaults to prefix. Both strings are literal. A missing key in an
existing table is a native no-op; an absent table is an error. Removing its last
binding can delete the table, so repeated removal need not succeed. No bulk
deletion, reset or retry is implicit. Blocks under shared preflight/dispatch
limits. Success acknowledges removal and hooks; it cannot undo earlier key
execution. Native errors and uncertain outcomes retain their diagnostics.

See also: [bind-key](#bind-key-function), [error-outcome](#error-outcome-function), [list-keys](#list-keys-function).

[Source](../src/key-bindings.lisp)

<a id="unlink-window-function"></a>

### unlink-window

`(unlink-window client link &key kill-if-last cancel-token timeout output-limit)`

Remove the captured LINK and return a COMMAND-OUTCOME without a value.
Tmux refuses the last reference unless KILL-IF-LAST is explicit; group membership
affects that check. Removing a last link can destroy its window and session.
Signals STALE-TARGET or an operational condition. Does not refresh a deleted link.

[Source](../src/placement.lisp)

<a id="unset-environment-function"></a>

### unset-environment

`(unset-environment client name &key scope target cancel-token timeout output-limit)`

Delete NAME from one raw tmux environment table and return its outcome.
SCOPE/TARGET follow SET-ENVIRONMENT. Absence remains tmux's native idempotent
unset behavior. This is distinct from REMOVE-ENVIRONMENT's tombstone; use
SET-ENVIRONMENT to store a present value.

See also: [remove-environment](#remove-environment-function), [set-environment](#set-environment-function).

[Source](../src/configuration-operations.lisp)

<a id="unset-hook-function"></a>

### unset-hook

`(unset-hook client name &key scope target (key nil key-p) cancel-token timeout output-limit)`

Remove one registered hook or hook-array entry and return its outcome.
SCOPE/TARGET and KEY follow SET-HOOK. The ordinary path never uses set-hook -R,
but tmux may run a remaining native after-hook as a consequence of this
set-hook command. The operation does not retry and validates the exact live
catalog before payload dispatch.

See also: [set-hook](#set-hook-function).

[Source](../src/configuration-operations.lisp)

<a id="unset-option-function"></a>

### unset-option

`(unset-option client name &key scope target (key nil key-p) cancel-token timeout output-limit)`

Remove one local option or array entry and return its COMMAND-OUTCOME.
SCOPE/TARGET and KEY follow SET-OPTION. The exact live catalog validates the
name, table and array shape before payload dispatch. Tmux's native unset/default
behavior applies; inherited state is not silently materialized. See SET-OPTION
for setting and scope rules. Never retries.

See also: [set-option](#set-option-function).

[Source](../src/configuration-operations.lisp)

<a id="wait-for-function"></a>

### wait-for

`(wait-for client channel &key (operation :wait) cancel-token timeout output-limit)`

Wait, signal, lock or unlock the literal CHANNEL; return a COMMAND-OUTCOME.
OPERATION is :WAIT (default), :SIGNAL, :LOCK or :UNLOCK. CHANNEL is a nonempty
string without NUL. This call performs I/O on an existing daemon. :WAIT and
:LOCK require tmux 3.8, whose client-loss handling removes queued waiters;
older daemons signal UNSUPPORTED-CAPABILITY before dispatch. :SIGNAL and
:UNLOCK support the library's tmux floor.

A signal wakes current waiters or retains one pending wake. Repeated signals
are not an idempotent latch or a counting semaphore. Locks have no owner and
survive this call and CLOSE-CLIENT within the daemon's lifetime; unlock them
explicitly. Continuation does not identify a sender; server shutdown can flush
waiting requests. Signals and locks
share a channel, so applications should use separate names for those protocols.

One operation owns CLIENT at a time. Use another client to signal or unlock
a blocked call. TIMEOUT and OUTPUT-LIMIT cover preflight and waiting together.
Cancellation or lost acknowledgement can leave signal consumption or a lock
grant uncertain; inspect ERROR-OUTCOME. Never retries or unlocks automatically.
Signals INVALID-ARGUMENT, COMMAND-FAILED or an operational condition.

See also: [cancel](#cancel-function), [close-client](#close-client-function), [error-outcome](#error-outcome-function), [outcome-status](#outcome-status-function), [unsupported-capability](#unsupported-capability-type).

[Source](../src/server-operations.lisp)

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

<a id="with-daemon-function"></a>

### with-daemon

`(with-daemon (name &rest options) &body body)`

Bind a newly started daemon and stop the original owner on every exit.
Accepts START-DAEMON keyword options and body declarations. Preserves multiple
values and the primary nonlocal exit. A cleanup failure after normal completion
signals; during an existing exit it is retained for explicit inspection/retry.

See also: [pending-daemon-cleanups](#pending-daemon-cleanups-function), [start-daemon](#start-daemon-function), [stop-daemon](#stop-daemon-function).

[Source](../src/daemon.lisp)

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

<a id="configuration-read-failed-type"></a>

### configuration-read-failed

A decoded acquisition failed, retaining prior records and native outcomes.
ERROR-CAUSE identifies the failure. ERROR-OUTCOME retains cause-associated or current
leaf evidence, possibly NIL before the associated read. Its status can be success
when decoding or diagnostics failed. No transport failure becomes absence.
No mutation is retried.

See also: [configuration-error-name](#configuration-error-name-function), [configuration-error-scope](#configuration-error-scope-function), [configuration-partial-records](#configuration-partial-records-function), [configuration-read-outcomes](#configuration-read-outcomes-function), [error-cause](#error-cause-function).

[Source](../src/configuration-acquisition.lisp)

Direct supertypes: [command-failed](#command-failed-type).

<a id="daemon-type"></a>

### daemon

An explicitly owned foreground tmux daemon and its supervisor.
Create it with START-DAEMON and release it with STOP-DAEMON or WITH-DAEMON.
Ordinary connection clients are separate resources; closing one leaves this
daemon alive. The owner retains failed cleanup work until an explicit retry.

See also: [start-daemon](#start-daemon-function), [stop-daemon](#stop-daemon-function), [with-daemon](#with-daemon-function).

[Source](../src/daemon.lisp)

Direct supertypes: `standard-object`.

<a id="daemon-cleanup-failed-type"></a>

### daemon-cleanup-failed

Owned daemon cleanup is incomplete and remains retryable.
ERROR-DAEMON retains the owner. Inspect DAEMON-CLEANUP-FAILURES and retry
STOP-DAEMON; no replacement daemon is started.

See also: [daemon-cleanup-failures](#daemon-cleanup-failures-function), [error-daemon](#error-daemon-function), [stop-daemon](#stop-daemon-function).

[Source](../src/daemon.lisp)

Direct supertypes: [cleanup-failed](#cleanup-failed-type).

<a id="daemon-start-failed-type"></a>

### daemon-start-failed

Managed startup failed; ERROR-CAUSE and ERROR-DAEMON retain evidence.
Startup attempts cleanup before propagating this condition. Incomplete cleanup
also remains discoverable through PENDING-DAEMON-CLEANUPS.

See also: [error-cause](#error-cause-function), [error-daemon](#error-daemon-function), [stop-daemon](#stop-daemon-function).

[Source](../src/daemon.lisp)

Direct supertypes: [libtmux-error](#libtmux-error-type).

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

Captured target authority or required dispatch context no longer agrees with live state.

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

The selected runtime lacks a qualified backend or required facility.
ERROR-FEATURE identifies the requirement; ERROR-CAUSE retains a failed probe
when available. OPEN-CLIENT checks the profile before resolving PROGRAM.

See also: [error-cause](#error-cause-function), [error-feature](#error-feature-function), [open-client](#open-client-function).

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
