# Persistent commands and pane output

Use the optional `libtmux/control` system when several commands or a pane-output
stream should share one connection. Core acquisition and captured objects keep
their existing contracts. Control commands do not refresh earlier observations.

The current control backend requires the core SBCL/Linux runtime profile and an
actual tmux daemon at least 3.7. Core operations still support tmux 3.3a through
3.8. Endpoint CI exercises control on 3.8 and verifies rejection before launch
on 3.3a. Reconnect and automatic replay are unavailable.

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
Ordinary notifications remain raw line bytes; no Lisp reader evaluates them.

Requests, reply bytes, event count and event bytes have separate limits set by
[`open-connection`](control-api.md#open-connection-function). The event queue
drops oldest events on overflow and reports `:gap` with event and byte counts.
An oversized new event reports loss while retaining earlier smaller events.
A reply limit failure ends the connection and retains its cause.

After retained events, `:end` reports reason, exit code, diagnostics, wire tail
and cause. Subsequent reads return end immediately. Inspect
[`connection-failure`](control-api.md#connection-failure-function) for a worker
failure; conditions retain identity while public byte containers are fresh.

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

See the [generated reference](control-api.md), [transport](transport.md#persistent-control-implementation),
[capability limits](capabilities.md) and [native example](../examples/control.lisp).
