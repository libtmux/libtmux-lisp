# Persistent commands and pane output

Use the optional `libtmux/control` system when several commands or a
pane-output stream should share one connection.

- Control commands do not refresh earlier observations.
- Control needs the core SBCL/Linux runtime profile and tmux 3.8 or newer.
  Core operations still work on tmux 3.3a or newer.
- Older daemons are refused before control mode starts. tmux 3.8 defers native
  notifications until a command reply ends, so replies stay clean. See the
  [architecture decision](adr/0001-native-common-lisp-engine.md#qualify-control-mode-and-source-filtering-before-exposing-them).
- Reconnection is explicit and returns fresh observations. There is no
  automatic reconnection or replay.

## Run a complete example

After [contributor setup](../.github/CONTRIBUTING.md#setup), run this program
from the checkout. Set `LIBTMUX_PROGRAM` to the native tmux binary when needed.

```console
$ mise exec -- tools/lisp.sh examples/control.lisp
```

The program:

- Owns an isolated daemon and creates a `/bin/cat` pane.
- Queues literal input and Enter, then waits for command completion.
- Reads output notifications until the pane has emitted the expected bytes.
- Prints `CONTROL PASS` with the received byte count.

This function comes from the
[complete executable program](../examples/control.lisp). Its `tm` and `control`
nicknames are `libtmux` and `libtmux.control`.

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
argv sequence and returns a request handle promptly.

- `:effect :read` or `:effect :mutation` is required. It records intent only.
- The raw interface does not validate captured targets or restrict command
  names.
- One worker serializes requests and reads the connection. Application code
  never runs as a callback in that worker.

[`await-request`](control-api.md#await-request-function):

- Returns two values: an owned result plist and `:ready`, or `nil` and
  `:timeout`.
- A wait timeout leaves the request live.
- A request's own deadline starts at submission, so queue time counts.
- `:timeout 0` polls without blocking; `nil` waits without bound.

Results hold `:status`, output octets, an unterminated wire tail, truncation,
caller effect, dispatch evidence, reason and reply count.

- Completion means the queue reached its completion marker. It does not prove
  input consumption or application readiness; check pane output separately, as
  the example does.
- Only framed replies enter result output. Other unframed command output
  stays available as raw notification events.

[`cancel-request`](control-api.md#cancel-request-function):

- Removes queued work without closing the connection.
- On active work, closes the connection and retires unissued queued work.
- The worker records write progress before publishing `:cancelled`.
- If completion won first, cancellation returns false and keeps that result.
- A dispatched command may already have taken effect. Cancellation does not
  roll it back, and no mutation is retried.

## Output, loss and end

[`next-event`](control-api.md#next-event-function):

- Returns an owned event and `:ready`, or `nil` and `:timeout`.
- Pane `:output` events keep raw octets, including NUL and invalid UTF-8.
  Decode text only when you know the encoding.
- Other notifications are raw line bytes without LF, including unknown labels
  and bytes. No Lisp reader evaluates them.
- A native `%exit` line stays a notification; transport EOF separately
  produces `:end`.
- Unsolicited command frames use `:reply`, with bytes and `:failed-p`.

[`open-connection`](control-api.md#open-connection-function) sets separate
limits for requests, reply bytes, event count and event bytes.

- On overflow the event queue drops the oldest events and reports `:gap` with
  event and byte counts.
- An oversized new event reports loss and keeps earlier smaller events.
- A reply-limit failure ends the connection and keeps its cause.

Flow control:

- Local dropping does not apply backpressure to tmux.
- Native `%pause` and `%continue` stay ordinary notifications, independent of
  `:gap` reporting.
- `refresh-client -A` changes native flow state. The library never issues it
  automatically.

Ending:

- After retained events, `:end` reports reason, exit code, diagnostics, wire
  tail and cause. Later reads return end immediately.
- Inspect
  [`connection-failure`](control-api.md#connection-failure-function) for a
  worker failure. Conditions keep identity; public byte containers are fresh.

## Observe native notifications

This function from the [complete program](../examples/control.lisp) renames a
window with an explicit [`rename-window`](api.md#rename-window-function)
operation and observes it through raw notification bytes.

- The example matches a known ASCII name. It does not decode arbitrary
  notification payloads as text.
- The returned bytes stay usable after the connection closes.
- The captured window keeps its earlier name. Acquire a replacement when you
  need current values.

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

[`with-connection`](control-api.md#with-connection-function):

- Closes the original resource on normal return, errors and nonlocal exits.
- Preserves declarations and all body values. Rebinding the visible variable
  cannot redirect cleanup.
- Closing a core client does not close its separate control connection.

[`close-connection`](control-api.md#close-connection-function):

- Joins the owned worker and releases process resources. The daemon stays
  alive.
- Has cleanup budgets beyond request deadlines; see the
  [process timing contract](transport.md).
- Is harmless to repeat after successful cleanup.
- On cleanup failure, exposes the connection through
  [`error-connection`](control-api.md#error-connection-function) and keeps the
  original cause in [`libtmux:error-cause`](api.md#error-cause-function).
  Retry close explicitly.
- [`pending-cleanups`](control-api.md#pending-cleanups-function) returns a
  fresh vector of resources still needing recovery.

Cleanup failures inside a scope:

- After a normal body return, a cleanup failure propagates.
- During a primary error or nonlocal exit, the scope keeps that exit and
  records the last 16 close failures on the connection. Read them with
  [`connection-cleanup-failures`](control-api.md#connection-cleanup-failures-function).

## Reconnect with fresh observations

[`reconnect`](control-api.md#reconnect-function) retires the old connection and
returns two values: a fresh connection and a complete captured snapshot.

- [`with-reconnection`](control-api.md#with-reconnection-function) binds both
  and closes the new resource reliably.
- The original core client must stay open.
- Omitted queue/reply limits inherit from the old connection. Supplied limits
  must be positive integers.
- The call blocks while it validates, retires, recaptures and attaches.
- It replays no requests or events.

This function, from the same program, checks the generation change, runs a
request on the new connection and returns owned pane data after both scopes
close.

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

Who can reconnect:

- Reconnection uses the original client context, daemon witness and exact
  session ID. It refuses a replacement session even if the old name is reused.
- A closed or naturally disconnected connection can reconnect while that origin
  stays valid.
- A different daemon or client needs explicit acquisition and
  [`open-connection`](control-api.md#open-connection-function).

After retiring the old resource, reconnect advances the core client's
generation before it next checks cancellation or expiry.

- Earlier core observations from that client become stale for operations. Their
  captured values stay readable.
- Use the returned snapshot's entities for later core commands.
- The snapshot precedes the new attachment, so it does not contain the newly
  attached frontend.
- Other independently owned control connections stay separate.

Old requests and streams:

- Old request handles keep their terminal results and partial dispatch
  evidence.
- Unissued queued work closes without dispatch.
- An issued mutation may already have taken effect. Reconnect neither rolls it
  back nor repeats it.
- Read the old event stream for retained output, gaps and its end result; read
  the new connection for new events. Neither implies continuity across the
  cutover.

Failure cases:

- Validation failure before retirement leaves an otherwise live old connection
  alone.
- Old cleanup failure keeps that resource and prevents new attachment.
- After retirement, a failed recapture or startup leaves the old resource
  closed and its generation advanced. Generation changes are not rolled back.
- Startup failure exposes the new candidate through
  [`connection-start-failed`](control-api.md#connection-start-failed-type).
  Inspect and close it, then acquire fresh observations and open explicitly.

Concurrency:

- One core operation lease, token, deadline and capture-output budget cover the
  cutover. Competing core work signals `libtmux:client-busy`.
- Existing cleanup and platform work can extend caller wall time.
- No control mutex is held during captures or worker joins.
- The public close generic runs on the caller thread, including application
  methods. Callbacks never run in the transport reader.

Attach behavior:

- Open and reconnect both preserve stored session environment values with
  tmux's `attach-session -E`.
- Native attach hooks and daemon lifecycle policies still apply.
- A guarded ready marker checks the preflight daemon after attachment. A
  refused candidate may appear briefly before cleanup.

See the [generated reference](control-api.md), [transport](transport.md#persistent-control-implementation),
[capability limits](capabilities.md) and [native example](../examples/control.lisp).
