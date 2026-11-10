<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="../../docs/assets/logo.svg" type="image/svg+xml">
    <img src="../../docs/assets/logo-512.png" width="128" height="128" alt="libtmux for Common Lisp">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# libtmux/workspace/cli

</div>

Validate workspace files, inspect ownership, preview changes and explicitly
apply them to a selected tmux endpoint. This ASDF system depends on
[`libtmux/workspace`](../README.md) and adds no external library.

## Run from source

Complete the root [source setup](../../README.md#install-from-source), including
locked dependencies. Run the shipped entry point from the checkout root:

```console
$ bin/libtmux-workspace validate examples/owned-workspace.json
```

Success reports `"status":"valid"`, schema `libtmux.lisp.workspace/2`, two
windows and three panes. Validation reads the bounded document without
contacting tmux. Display the command grammar:

```console
$ bin/libtmux-workspace --help
```

Owned plan, apply and inspect require `--socket-path`; pass `--program` when
tmux is not the native binary selected by `PATH`. The standalone `--reconcile`
flag permits owned plan/apply changes; a preview grants no execution authority.
Legacy `/1` files also support an offline plan without a daemon.

See the [CLI guide](../../docs/workspace-owned.md#use-the-cli) for result and
failure contracts. The [example runner](../../tools/examples.py) executes cold
validation, preview, apply, no-op reapplication, reconciliation and stopped-work
inspection through this entry point on its owned server. Run the complete
checks from the checkout root:

```console
$ mise run examples
```

## Embed and handle results

Load the command-line adapter explicitly:

```lisp
(asdf:load-system "libtmux/workspace/cli")
```

[`main`](../../docs/workspace-api.md#main-function) returns an exit code
without terminating the Lisp image or closing caller-owned streams. Success
uses code 0, invalid usage code 2 and document or operational failure code 1.
Failures write structured JSON to stderr and retain command evidence. Completed
inspection returns 0 even for busy or invalid ownership; read completion differs
from readiness. Do not automatically retry an uncertain apply.

[Workspace library](../README.md) · [CLI API](../../docs/workspace-api.md#command-line-adapter) ·
[Changelog](../../CHANGELOG.md) · [MIT](../../LICENSE)
