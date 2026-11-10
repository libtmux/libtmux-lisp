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

## Load and run

Complete the root [source setup](../README.md#install-from-source), then load:

```lisp
(asdf:load-system "libtmux/control")
```

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

[`submit-command`](../docs/control-api.md#submit-command-function) queues a
request; queuing alone does not establish command completion.
[`await-request`](../docs/control-api.md#await-request-function) and
[`next-event`](../docs/control-api.md#next-event-function) may block up to their
specified waits. Timeout, end of stream and queue loss remain distinct results.
Pane output is bytes and may not be valid UTF-8.

Use [`with-connection`](../docs/control-api.md#with-connection-function) for
resource ownership. Reconnection is explicit, renews the generation and returns
fresh observations; it never replays uncertain commands. Earlier captured
objects retain their values. Broader event qualification remains in development.

[Control guide](../docs/control.md) · [API](../docs/control-api.md) ·
[Capabilities](../docs/capabilities.md) · [Changelog](../CHANGELOG.md) ·
[MIT](../LICENSE)
