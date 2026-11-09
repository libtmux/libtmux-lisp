# Persistent control API

Generated from live package documentation and signatures by `mise run docs`.
Edit source docstrings; `mise run check` detects drift.

[Control guide](control.md) · [Transport contract](transport.md)

Persistent native tmux commands and bounded byte events.
Load the optional LIBTMUX/CONTROL system. The qualified backend requires the
core SBCL/Linux profile and an actual tmux daemon >=3.8. Connections own a
worker and process independently of their originating LIBTMUX:CLIENT.
Submission is nonblocking; waits use condition notifications. One worker
serializes requests and reads all protocol data. No application callback
runs in that worker. Commands use tmux argv, not shell source.
Results and events own their mutable bytes and containers. A completed
command queue does not establish application readiness. No automatic replay
or reconnect occurs. Explicit RECONNECT renews the original core client's
generation and returns fresh observations.
See also: WITH-CONNECTION, WITH-RECONNECTION, SUBMIT-COMMAND, NEXT-EVENT.

## Functions

<a id="await-request-function"></a>

### await-request

`(await-request request &key (timeout 30))`

Wait for owned result/:READY, or return NIL/:TIMEOUT without cancelling.
TIMEOUT is nonnegative real seconds or NIL for an unbounded wait. Zero polls.
The result plist contains :STATUS, :OUTPUT bytes, :WIRE-TAIL bytes,
:TRUNCATED-P, :EFFECT, :DISPATCHED-P, :REASON and :REPLY-COUNT. Wire tail is
unterminated protocol data, not decoded output. Positive stdin progress makes
DISPATCHED-P true conservatively, even for an incomplete line. A dispatched
failed/cancelled/timed-out/closed request may have effects; never infer rollback.
COMPLETED means the command queue reached its marker, not application readiness.
Only framed replies enter OUTPUT; unframed lines remain notification events.
Repeated awaits return fresh byte storage. No exception hides a terminal result.

See also: [cancel-request](#cancel-request-function), [next-event](#next-event-function), [submit-command](#submit-command-function).

[Source](../src/control.lisp)

<a id="cancel-request-function"></a>

### cancel-request

`(cancel-request request)`

Request cancellation; return true only when this call changes live work.
Queued work is removed without dispatch or connection closure. Active work
closes its connection and retires unissued queued requests. The worker records
write progress before publishing :CANCELLED; await it to inspect that evidence.
Cancellation winning before completion preserves :CANCELLED; an already terminal
request is unchanged. No command is replayed and dispatched effects are not undone.

See also: [await-request](#await-request-function), [close-connection](#close-connection-function), [request-state](#request-state-function).

[Source](../src/control.lisp)

<a id="close-connection-function"></a>

### close-connection

`(close-connection connection)`

Close this connection's worker and process; return NIL after cleanup.
Leave the tmux daemon running. Concurrent closes serialize; repeated successful
close is harmless. In-flight results retain partial output and dispatch state.
Cleanup can add time beyond request deadlines. Failure signals
CONNECTION-CLEANUP-FAILED and retains this resource for explicit retry.

See also: [connection-cleanup-failures](#connection-cleanup-failures-function), [pending-cleanups](#pending-cleanups-function), [with-connection](#with-connection-function).

[Source](../src/control.lisp)

<a id="connection-cleanup-failures-function"></a>

### connection-cleanup-failures

`(connection-cleanup-failures connection)`

Return a fresh vector of the last 16 close failures, newest first. No I/O.
Condition objects are retained by identity. WITH-CONNECTION records secondary
cleanup failures while preserving an existing body error or nonlocal exit.

See also: [close-connection](#close-connection-function), [pending-cleanups](#pending-cleanups-function).

[Source](../src/control.lisp)

<a id="connection-failure-function"></a>

### connection-failure

`(connection-failure connection)`

Return the retained worker failure condition, or NIL, without I/O.
Conditions retain identity; byte data comes from NEXT-EVENT or AWAIT-REQUEST.

See also: [connection-cleanup-failures](#connection-cleanup-failures-function), [connection-state](#connection-state-function).

[Source](../src/control.lisp)

<a id="connection-state-function"></a>

### connection-state

`(connection-state connection)`

Return :STARTING, :READY, :CLOSING or :CLOSED without I/O.
This is an observation, not a lease for subsequent submission.

See also: [connection-failure](#connection-failure-function), [submit-command](#submit-command-function).

[Source](../src/control.lisp)

<a id="error-connection-function"></a>

### error-connection

`(error-connection condition)`

Return the retained connection implicated in a CONNECTION-ERROR. No I/O.

See also: [close-connection](#close-connection-function), [libtmux:error-cause](api.md#error-cause-function).

[Source](../src/control.lisp)

<a id="next-event-function"></a>

### next-event

`(next-event connection &key (timeout 30))`

Wait for an owned event/:READY or NIL/:TIMEOUT on this connection.
TIMEOUT is nonnegative real seconds or NIL; zero polls. :OUTPUT has :PANE,
:AGE, :EXTENDED-P and :DATA octets, preserving invalid UTF-8. :NOTIFICATION
contains a raw line without LF in :DATA, preserving unknown labels and bytes.
Native %exit is a notification; transport end is reported independently.
Unsolicited :REPLY also has :FAILED-P.
:GAP reports :EVENTS and :BYTES dropped from the bounded queue. An oversized
new event reports loss without discarding retained smaller events.
Local loss does not pause tmux. Native pause/continue notices remain raw
notifications and are distinct from local :GAP delivery.
:END follows retained events, with :REASON, :EXIT-CODE, :DIAGNOSTICS bytes,
:WIRE-TAIL bytes and :CAUSE. After end, repeated reads return end immediately.
Causes retain condition identity. No application callback executes in the reader.

See also: [await-request](#await-request-function), [connection-failure](#connection-failure-function), [open-connection](#open-connection-function).

[Source](../src/control.lisp)

<a id="open-connection-function"></a>

### open-connection

`(open-connection client session &key (timeout 30) (request-limit 16) (event-limit 256) (event-byte-limit 4194304) (reply-byte-limit 1048576))`

Attach a separate owned control connection to a captured SESSION.
CLIENT supplies the core endpoint and authority. Startup preflights the target
and requires the live daemon to be >=3.8. TIMEOUT bounds startup admission and
supervised execution; platform preparation and cleanup add caller wall time.
REQUEST-LIMIT includes active and queued work. Events drop oldest entries at
EVENT-LIMIT or EVENT-BYTE-LIMIT and report loss. REPLY-BYTE-LIMIT bounds each
request's retained output; overflow closes the connection with a cause.
This call blocks until ready or failed. All limits must be positive integers
except the nonnegative real TIMEOUT. No daemon is started or terminated.
Attachment preserves the stored session environment; native attach hooks and
server lifecycle policies still apply. Readiness checks the observed daemon
witness after attachment, so a refused candidate may have appeared briefly.

See also: [close-connection](#close-connection-function), [next-event](#next-event-function), [reconnect](#reconnect-function), [submit-command](#submit-command-function), [with-connection](#with-connection-function).

[Source](../src/control.lisp)

<a id="pending-cleanups-function"></a>

### pending-cleanups

`(pending-cleanups)`

Return a fresh vector of connections retaining failed cleanup work. No I/O.
Retry CLOSE-CONNECTION explicitly. Successful close removes the entry.

See also: [connection-cleanup-failed](#connection-cleanup-failed-type), [error-connection](#error-connection-function).

[Source](../src/control.lisp)

<a id="reconnect-function"></a>

### reconnect

`(reconnect connection &key (timeout 30) (request-limit nil request-limit-p) (event-limit nil event-limit-p) (event-byte-limit nil event-byte-limit-p) (reply-byte-limit nil reply-byte-limit-p))`

Retire CONNECTION and return a fresh connection and complete snapshot.
Use the original core client and exact session ID. The client must remain open
in the original generation. Explicitly supplied limits must be positive integers;
omitted queue/reply limits inherit the old connection. TIMEOUT is nonnegative
real seconds shared across preflight, retirement, recapture and startup;
preparation and cleanup can add wall time. Capture output shares the core
client's output budget. Concurrent core work signals LIBTMUX:CLIENT-BUSY.
Preflight refusal leaves a live old connection alone. After successful close,
renew the core generation even if later work fails. Every earlier core capture
from that client becomes stale for operations, while local data remains usable.
The returned snapshot precedes new attachment; it does not include that new
frontend. A closing/closed old resource remains reconnectable with valid origin.
Old requests/results/events stay on the retired resource. Pending work is closed,
never replayed; dispatched effects can remain uncertain. Other separately owned
control resources remain independent. No event continuity or replay is implied.
The CLOSE-CONNECTION generic runs on the caller thread; its failures are retained.
CONNECTION-STALE refuses changed origin/session/daemon. Old cleanup failures
retain the old resource; startup failures retain the new candidate through
CONNECTION-START-FAILED. After failed cutover, acquire/select and open anew.
Use WITH-RECONNECTION or close the returned resource explicitly.

See also: [await-request](#await-request-function), [close-connection](#close-connection-function), [connection-stale](#connection-stale-type), [with-reconnection](#with-reconnection-function).

[Source](../src/control.lisp)

<a id="request-state-function"></a>

### request-state

`(request-state request)`

Return retained request state without I/O.
States are :QUEUED, :WRITING, :RUNNING, :COMPLETED, :FAILED, :TIMED-OUT,
:CANCELLED and :CLOSED. A terminal result is never replaced by cancellation.

See also: [await-request](#await-request-function), [cancel-request](#cancel-request-function).

[Source](../src/control.lisp)

<a id="submit-command-function"></a>

### submit-command

`(submit-command connection argv &key effect (timeout 30))`

Queue copied tmux ARGV and return a REQUEST without waiting for its reply.
EFFECT must explicitly be :READ or :MUTATION; it records caller intent, not a
command restriction. TIMEOUT is a nonnegative real deadline budget starting at
submission, including queue time. A zero budget can expire before dispatch.
Commands execute serially. Full queues signal CONNECTION-BUSY; closing ones
signal CONNECTION-CLOSED. Use argv for tmux syntax, not shell interpolation.
This raw path does not validate or refresh captured operational targets.

See also: [await-request](#await-request-function), [cancel-request](#cancel-request-function), [request-state](#request-state-function).

[Source](../src/control.lisp)

<a id="with-connection-function"></a>

### with-connection

`(with-connection (name client session &rest options) &body body)`

Bind NAME to a control connection and close the original resource on exit.
Evaluate CLIENT, SESSION and OPEN-CONNECTION options once. BODY accepts
declarations and returns all its values. Rebinding NAME cannot redirect cleanup.
After normal return, propagate cleanup failure; during an error or nonlocal
exit, preserve that exit and record cleanup failure on the connection.

See also: [close-connection](#close-connection-function), [connection-cleanup-failures](#connection-cleanup-failures-function), [open-connection](#open-connection-function).

[Source](../src/control.lisp)

<a id="with-reconnection-function"></a>

### with-reconnection

`(with-reconnection (name snapshot previous &rest options) &body body)`

Bind a fresh NAME and SNAPSHOT from explicit RECONNECT; close NAME on exit.
Evaluate PREVIOUS and options once. BODY permits declarations and returns all
values. Rebinding either visible name cannot redirect cleanup. Preserve primary
errors/nonlocal exits and record secondary cleanup errors on the new connection.
The previous resource retains its own old results and events.

See also: [connection-cleanup-failures](#connection-cleanup-failures-function), [reconnect](#reconnect-function), [with-connection](#with-connection-function).

[Source](../src/control.lisp)

## Classes and conditions

These resources and conditions retain native connection/request state; their slots are private.

<a id="connection-type"></a>

### connection

An owned persistent tmux connection with one protocol worker.
Use WITH-CONNECTION or CLOSE-CONNECTION to release it. Closing the originating
core client does not close this resource. Captured core observations remain
separate; raw control commands do not refresh them. RECONNECT requires that
original core client to remain open.

See also: [connection-state](#connection-state-function), [open-connection](#open-connection-function), [pending-cleanups](#pending-cleanups-function), [reconnect](#reconnect-function).

[Source](../src/control.lisp)

Direct supertypes: `standard-object`.

<a id="connection-busy-type"></a>

### connection-busy

The bounded request queue, including active work, is full.
Submission did not dispatch this command. See also: SUBMIT-COMMAND.

[Source](../src/control.lisp)

Direct supertypes: `connection-error`, `client-busy`.

<a id="connection-cleanup-failed-type"></a>

### connection-cleanup-failed

Closing failed; retry CLOSE-CONNECTION on ERROR-CONNECTION.
The resource remains discoverable through PENDING-CLEANUPS. No mutation is
replayed. See also: CONNECTION-CLEANUP-FAILURES, LIBTMUX:ERROR-CAUSE.

[Source](../src/control.lisp)

Direct supertypes: `connection-error`, `cleanup-failed`.

<a id="connection-closed-type"></a>

### connection-closed

Submission attempted on a closing or closed connection.

See also: [connection-state](#connection-state-function), [submit-command](#submit-command-function).

[Source](../src/control.lisp)

Direct supertypes: `connection-error`, `client-closed`.

<a id="connection-error-type"></a>

### connection-error

A control failure retaining its connection and original cause.

See also: [libtmux:error-cause](api.md#error-cause-function), [error-connection](#error-connection-function).

[Source](../src/control.lisp)

Direct supertypes: `libtmux-error`.

<a id="connection-stale-type"></a>

### connection-stale

The original control client generation, daemon or session changed.
ERROR-CONNECTION and LIBTMUX:ERROR-TARGET retain the old public connection.
Acquire fresh observations and use OPEN-CONNECTION explicitly; stale authority
cannot authorize reconnection to a replacement target. No request is replayed.

See also: [libtmux:error-cause](api.md#error-cause-function), [reconnect](#reconnect-function), [libtmux:stale-target](api.md#stale-target-type).

[Source](../src/control.lisp)

Direct supertypes: `connection-error`, `stale-target`.

<a id="connection-start-failed-type"></a>

### connection-start-failed

Startup failed after allocating a connection resource.
ERROR-CONNECTION retains the resource even if cleanup also failed. Core
argument and unsupported-capability errors before allocation stay core types.

See also: [close-connection](#close-connection-function), [open-connection](#open-connection-function), [pending-cleanups](#pending-cleanups-function).

[Source](../src/control.lisp)

Direct supertypes: `connection-error`, `command-failed`.

<a id="request-type"></a>

### request

One queued command and its retained dispatch/result evidence.
Keep this handle to await or cancel work. A wait timeout leaves it live.

See also: [await-request](#await-request-function), [cancel-request](#cancel-request-function), [submit-command](#submit-command-function).

[Source](../src/control.lisp)

Direct supertypes: `standard-object`.
