# Persistent commands and pane output

Use the optional `libtmux/control` system when several commands or a pane-output
stream should share one connection. Core acquisition and captured objects keep
their existing contracts. Control commands do not refresh earlier observations.

The current control backend requires the core SBCL/Linux runtime profile and an
actual tmux daemon at least 3.8. Core operations still support tmux 3.3a through
3.8. Endpoint CI exercises control on 3.8 and verifies rejection before launch
on 3.3a. Reconnection is explicit and returns fresh observations; automatic
reconnection and replay are unavailable.

Tmux 3.8 defers native notifications until a command reply ends. The earlier
3.7 series can include pause/continue notices inside replies, so this API
refuses those daemons before starting control mode. Core compatibility is
unchanged. See the [architecture decision](adr/0001-native-common-lisp-engine.md#qualify-control-mode-and-source-filtering-before-exposing-them).

## Run a complete example

After [contributor setup](../.github/CONTRIBUTING.md#setup), run this program from
the checkout. Set `LIBTMUX_PROGRAM` to the native tmux binary when needed.

```console
$ mise exec -- tools/lisp.sh examples/control.lisp
```

The program owns an isolated daemon, creates a `/bin/cat` pane, queues literal
input and Enter, waits for command completion, then reads output notifications
until the pane has emitted the expected bytes. Closing the connection leaves
the daemon running; the outer daemon scope then stops its owned fixture.
Successful execution prints `CONTROL PASS` with the received byte count.

The function below is extracted from the
[complete executable program](../examples/control.lisp). Its `tm` and `control`
package-local nicknames refer to `libtmux` and `libtmux.control`.

<!-- example:control -->
```lisp
(defun echo-through-control (client session pane)
  "Send literal text and collect pane-output bytes on one scoped connection."
  (control:with-connection (connection client session)
    (let ((write (control:submit-command
                  connection (list "send-keys" "-t" (tm:id pane) "-l" "hello from control")
                  :effect :mutation))
          (enter (control:submit-command
                  connection (list "send-keys" "-t" (tm:id pane) "Enter")
                  :effect :mutation)))
      (dolist (request (list write enter))
        (multiple-value-bind (result delivery) (control:await-request request :timeout 1)
          (assert (eq :ready delivery))
          (assert (eq :completed (getf result :status))))))
    (let ((bytes (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0))
          (expected (map 'vector #'char-code "hello from control"))
          (deadline (+ (get-internal-real-time) internal-time-units-per-second)))
      (loop repeat 64
            until (search expected bytes)
            for remaining = (/ (- deadline (get-internal-real-time)) internal-time-units-per-second)
            do (assert (plusp remaining))
               (multiple-value-bind (event delivery) (control:next-event connection :timeout remaining)
                 (assert (eq :ready delivery))
                 (case (getf event :kind)
                   (:output
                    (assert (string= (tm:id pane) (getf event :pane)))
                    (loop for byte across (getf event :data) do (vector-push-extend byte bytes)))
                   ((:gap :end) (error "Output stream ended or lost data: ~S" event)))))
      (assert (search expected bytes))
      (coerce bytes '(simple-array (unsigned-byte 8) (*))))))
```
<!-- /example -->

## Submission, completion and cancellation

[`submit-command`](control-api.md#submit-command-function) copies a finite tmux
argv sequence and returns a native request handle promptly. It requires an
explicit `:effect :read` or `:effect :mutation`. This records intent; the raw
command interface does not validate captured targets or restrict command names.
One worker serializes requests and reads the connection. Application code never
runs as a callback in that worker.

[`await-request`](control-api.md#await-request-function) returns two values: an
owned result plist and `:ready`, or `nil` and `:timeout`. A wait timeout leaves
the request live. Each request's own deadline starts at submission, so queue
time counts. `:timeout 0` polls without blocking; `nil` permits an unbounded wait.

Results retain `:status`, output octets, an unterminated wire tail, truncation,
caller effect, dispatch evidence, reason and reply count. Command completion
means the queue reached its completion marker. The example separately checks
pane output because completion does not prove input consumption or application
readiness. Only framed replies enter result output; other unframed command
output remains available as raw notification events.

[`cancel-request`](control-api.md#cancel-request-function) removes queued work
without closing the connection. Cancelling active work closes the connection
and retires unissued queued work. The worker records write progress before
publishing `:cancelled`. If completion won first, cancellation returns false
and preserves that result. A dispatched command may already have effects;
cancellation does not roll it back. No mutation is retried.

## Output, loss and end

[`next-event`](control-api.md#next-event-function) returns an owned event and
`:ready`, or `nil` and `:timeout`. Pane `:output` events retain raw octets,
including NUL and invalid UTF-8. Decode text only when its encoding is known.
Ordinary notifications remain raw line bytes without LF, including unknown
labels and bytes. No Lisp reader evaluates them. A native `%exit` line remains
a notification; transport EOF independently produces `:end`. Unsolicited
command frames use `:reply`, with bytes and `:failed-p` evidence.

Requests, reply bytes, event count and event bytes have separate limits set by
[`open-connection`](control-api.md#open-connection-function). The event queue
drops oldest events on overflow and reports `:gap` with event and byte counts.
An oversized new event reports loss while retaining earlier smaller events.
A reply limit failure ends the connection and retains its cause.

Local dropping does not apply backpressure to tmux. Native `%pause` and
`%continue` notices remain ordinary notifications, independent of local `:gap`
reporting. Commands such as `refresh-client -A` explicitly change native flow
state; the library does not issue them automatically.

After retained events, `:end` reports reason, exit code, diagnostics, wire tail
and cause. Subsequent reads return end immediately. Inspect
[`connection-failure`](control-api.md#connection-failure-function) for a worker
failure; conditions retain identity while public byte containers are fresh.

Local routing checks exercise the 24 labels found in the pinned 3.7/3.8 sources,
including both pane-output forms, unknown labels, reply context and chunked
ownership. Native 3.8 checks exercise representative topology, buffer and
pause/continue events alongside commands. These checks do not trigger every
native emitter, subscription timer or daemon policy. Larger stream and retained
memory measurements remain separate from this delivery contract.

## Observe native notifications

This function belongs to the [complete program](../examples/control.lisp) above.
It observes an explicit [`rename-window`](api.md#rename-window-function) operation
through raw notification bytes. The fixture uses a known ASCII name; it does
not decode arbitrary notification payloads as text. The returned bytes remain
usable after connection close. The captured window keeps its earlier name.
Acquire a replacement explicitly when current values are needed.

<!-- example:controlnotifications -->
```lisp
(defun observe-window-rename (client session window)
  "Rename explicitly and return its owned notification bytes."
  (let ((captured-name (tm:name window))
        (expected (map 'vector #'char-code
                       (format nil "%window-renamed ~A event-editors" (tm:id window)))))
    (control:with-connection (connection client session)
      (let ((outcome (tm:rename-window client window "event-editors" :observe nil)))
        (assert (eq :succeeded (tm:outcome-status outcome))))
      (let ((deadline (+ (get-internal-real-time) internal-time-units-per-second)))
        (loop for remaining = (/ (- deadline (get-internal-real-time)) internal-time-units-per-second)
              do (assert (plusp remaining))
                 (multiple-value-bind (event delivery) (control:next-event connection :timeout remaining)
                   (assert (eq :ready delivery))
                   (when (member (getf event :kind) '(:gap :end))
                     (error "Notification stream ended or lost data: ~S" event))
                   (when (and (eq :notification (getf event :kind))
                              (equalp expected (getf event :data)))
                     (assert (string= captured-name (tm:name window)))
                     (return (getf event :data)))))))))
```
<!-- /example -->

## Resource scopes and recovery

[`with-connection`](control-api.md#with-connection-function) closes the original
resource on normal return, errors and nonlocal exits. It preserves declarations
and all body values. Rebinding the visible variable cannot redirect cleanup.
Closing a core client does not close its separate control connection.

[`close-connection`](control-api.md#close-connection-function) joins the owned
worker and releases process resources. It leaves the daemon alive. Cleanup has
additional budgets beyond request deadlines; see the
[process timing contract](transport.md). Closing again after successful cleanup
is harmless. A cleanup failure exposes its connection through
[`error-connection`](control-api.md#error-connection-function) and retains the
original cause through [`libtmux:error-cause`](api.md#error-cause-function).
Retry close explicitly; [`pending-cleanups`](control-api.md#pending-cleanups-function)
returns a fresh vector of resources still needing recovery.

After a normal body return, cleanup failure propagates. During a primary error
or nonlocal exit, the scope preserves that exit and records the last 16 close
failures on the connection. Use
[`connection-cleanup-failures`](control-api.md#connection-cleanup-failures-function)
to inspect them.

## Reconnect with fresh observations

[`reconnect`](control-api.md#reconnect-function) retires the old connection and
returns two values: a fresh connection and a complete captured snapshot. Use
[`with-reconnection`](control-api.md#with-reconnection-function) to bind both
and close the new resource reliably. The original core client must remain open.
Omitted queue/reply limits inherit the old connection; supplied limits must be
positive integers. The call blocks while it validates, retires, recaptures and
attaches. It does not replay requests or events.

The following function comes from the same complete program above. It verifies
the generation change, executes a request on the new connection and returns
ordinary owned pane data after both resource scopes close.

<!-- example:controlreconnect -->
```lisp
(defun inspect-after-reconnect (client session)
  "Return owned pane data and provenance after an explicit generation change."
  (let ((before (getf (tm:provenance session) :generation)))
    (control:with-connection (old client session)
      (control:with-reconnection (connection snapshot old)
        (assert (eq :closed (control:connection-state old)))
        (assert (> (getf (tm:provenance snapshot) :generation) before))
        (let ((request (control:submit-command
                        connection '("display-message" "-p" "-l" "reconnected") :effect :read)))
          (multiple-value-bind (result delivery) (control:await-request request :timeout 1)
            (assert (eq :ready delivery))
            (assert (eq :completed (getf result :status)))))
        (values (map 'vector #'tm:entity-data (tm:panes snapshot))
                (tm:provenance snapshot))))))
```
<!-- /example -->

Reconnection uses the original client context, daemon witness and exact session
ID. It refuses a replacement session even if the old name is reused. A closed
or naturally disconnected connection can reconnect while that origin remains
valid. A different daemon or client requires explicit acquisition and
[`open-connection`](control-api.md#open-connection-function).

After successfully retiring the old resource, the operation advances the core
client's generation before checking cancellation or expiry again. All earlier
core observations from that client then become stale for operations; their
captured values remain readable. Use the returned snapshot's entities for
subsequent core commands. The snapshot precedes new attachment and does not
claim to contain the newly attached frontend. Other independently owned control
connections stay separate.

Old request handles retain their terminal results and partial dispatch evidence.
Unissued queued work closes without dispatch. An issued mutation can already
have effects; reconnection does not establish rollback or repeat it. Read the
old event stream for retained output, gaps and its end result; read the new
connection for new events. Neither stream implies continuity across cutover.

Validation failure before retirement leaves an otherwise live old connection
alone. Old cleanup failure retains that resource and prevents new attachment.
After retirement, a failed recapture or startup leaves the old resource closed
and its generation advanced. Startup failure exposes the new candidate through
[`connection-start-failed`](control-api.md#connection-start-failed-type);
inspect/close that retained resource, then acquire fresh observations and open
explicitly. Generation changes are not rolled back.

One core operation lease, token, deadline and capture-output budget cover the
cutover. Competing core work signals `libtmux:client-busy`. Existing cleanup and
platform work can extend caller wall time. No control mutex is held during
captures or worker joins. The public close generic runs on the caller thread,
including application methods; callbacks never run in the transport reader.

Both ordinary open and reconnect preserve stored session environment values
using tmux's `attach-session -E`. Native attach hooks and daemon lifecycle
policies still apply. A guarded ready marker checks the preflight daemon after
attachment; a refused candidate may have appeared briefly before cleanup.

See the [generated reference](control-api.md), [transport](transport.md#persistent-control-implementation),
[capability limits](capabilities.md) and [native example](../examples/control.lisp).
