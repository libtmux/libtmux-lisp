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

[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/lisp/)

</div>

Queue tmux requests and read pane output as bytes over one persistent
connection. Needs only core `libtmux`, and tmux 3.8 or newer even though core
works on older releases.

[Documentation](https://libtmux.org/en/lisp/) · [Control API][api-control]

## Load it

Do the root [source setup](../README.md#install-from-source) first, then:

```lisp
(asdf:load-system "libtmux/control")
```

## Queue requests and read pane output

### [`libtmux.control:with-connection`][api-with-connection]: one scoped connection

Its siblings: [`submit-command`][api-submit-command] queues a request,
[`await-request`][api-await-request] waits for its reply, and
[`next-event`][api-next-event] reads output.

This function queues literal text and Enter, awaits both replies, then collects
pane bytes until the text arrives. It takes an open core client, plus a session
and pane from its snapshot. `tm` is `libtmux` and `control` is
`libtmux.control`; the [complete program](../examples/control.lisp) defines both:

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

Run the program on its own daemon, with tmux 3.8 on `PATH`:

```console
$ mise exec -- tools/lisp.sh examples/control.lisp
```

It prints `CONTROL PASS`, `CONTROL NOTIFICATION PASS` and
`CONTROL RECONNECT PASS`.

More: [control guide](../docs/control.md) ·
[reconnecting](../docs/control.md#reconnect-with-fresh-observations)

## Delivery and limits

- **Queued is not done.** Queuing says nothing about completion.
- **Waits block.** `await-request` and `next-event` block up to the wait you
  give. A timeout, end of stream and queue loss are distinct results.
- **Output is bytes.** It may not be valid UTF-8.
- **Reconnecting is explicit.**
  [`libtmux.control:with-reconnection`][api-with-reconnection] renews the
  generation and returns fresh observations. It never replays uncertain
  commands; earlier captures keep their values.
- **Closing a connection leaves the daemon running.** Stop it from the scope
  that started it.
- **Event coverage is still growing.**
  [Capabilities and limits](../docs/capabilities.md).

[Control API][api-control] · [Changelog](../CHANGELOG.md) · [MIT](../LICENSE)

[api-await-request]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-await-request/
[api-control]: https://libtmux.org/en/lisp/latest/reference/libtmux-control/
[api-next-event]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-next-event/
[api-submit-command]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-submit-command/
[api-with-connection]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-with-connection/
[api-with-reconnection]: https://libtmux.org/en/lisp/latest/reference/libtmux-control-with-reconnection/
