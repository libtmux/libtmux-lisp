<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="../docs/assets/logo.svg" type="image/svg+xml">
    <img src="../docs/assets/logo-512.png" width="128" height="128" alt="libtmux for Common Lisp">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# libtmux/control

</div>

Queue tmux requests and consume pane-output bytes on a scoped persistent
connection. This optional ASDF system depends only on core `libtmux` and needs
the supported SBCL/Linux runtime profile with a tmux 3.8+ daemon. Core's wider
tmux 3.3a–3.8 support does not qualify control on earlier releases.

[Documentation](https://libtmux.org/en/lisp/) · [Control API][api-control]

## Load and run

Complete the root [source setup](../README.md#install-from-source), then load:

```lisp
(asdf:load-system "libtmux/control")
```

[`libtmux.control:with-connection`][api-with-connection] scopes a connection.
This function excerpt queues literal text and Enter, awaits both replies, then
collects pane-output bytes until the text arrives. Its arguments are an open
core client and a session and pane from that client's captured snapshot.
The [complete program](../examples/control.lisp) defines the local nicknames
`tm` for `libtmux` and `control` for `libtmux.control`:

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

The [complete control program](../examples/control.lisp) starts its own daemon,
queues writes, awaits replies, assembles streamed pane bytes, observes a window
rename and explicitly reconnects. Run it from the checkout root with tmux 3.8
on `PATH`:

```console
$ mise exec -- tools/lisp.sh examples/control.lisp
```

Success prints `CONTROL PASS`, `CONTROL NOTIFICATION PASS` and
`CONTROL RECONNECT PASS`. Closing the connection leaves its daemon running;
the outer owned-daemon scope performs final cleanup.

## Delivery and lifecycle

[`libtmux.control:submit-command`][api-submit-command] queues a
request; queuing alone does not establish command completion.
[`libtmux.control:await-request`][api-await-request] and
[`libtmux.control:next-event`][api-next-event] may block up to their
specified waits. Timeout, end of stream and queue loss remain distinct results.
Pane output is bytes and may not be valid UTF-8.

Use [`libtmux.control:with-connection`][api-with-connection] for
resource ownership. Reconnection is explicit, renews the generation and returns
fresh observations; it never replays uncertain commands. Earlier captured
objects retain their values. Broader event qualification remains in development.

[Control guide](../docs/control.md) · [API][api-control] ·
[Capabilities](../docs/capabilities.md) · [Changelog](../CHANGELOG.md) ·
[MIT](../LICENSE)

[api-await-request]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-await-request/
[api-control]: https://libtmux.org/en/lisp/latest/reference/libtmux-control/
[api-next-event]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-next-event/
[api-submit-command]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-submit-command/
[api-with-connection]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-with-connection/
