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

Validate workspace files, print local topology previews and explicitly apply
them to a selected tmux endpoint. This ASDF system depends on
[`libtmux/workspace`](../README.md) and adds no external library.

## Run from source

Complete the root [source setup](../../README.md#install-from-source), including
locked dependencies. Run the shipped entry point from the checkout root:

```console
$ bin/libtmux-workspace validate examples/workspace.json
```

Success is a JSON object with `"status":"valid"`, two windows and three panes.
Validation reads the bounded document without contacting tmux. Preview the
creation steps locally:

```console
$ bin/libtmux-workspace plan examples/workspace.json
```

Application requires `--socket-path`; pass `--program` when tmux is not the
native binary selected by `PATH`. See the
[CLI guide](../../docs/workspaces.md#use-the-cli-without-an-implicit-server)
for complete setup and endpoint selection. The
[example runner](../../tools/examples.py) executes validation, preview, apply
and zero-mutation reapplication on its owned server.

## Embed and handle results

Load the command-line adapter explicitly:

```lisp
(asdf:load-system "libtmux/workspace/cli")
```

[`main`](../../docs/workspace-api.md#main-function) returns an exit code
without terminating the Lisp image or closing caller-owned streams. Success
uses code 0, invalid usage code 2 and document or operational failure code 1.
Failures write structured JSON to stderr and retain command evidence. Do not
automatically retry an uncertain apply.

[Workspace library](../README.md) · [CLI API](../../docs/workspace-api.md#command-line-adapter) ·
[Changelog](../../CHANGELOG.md) · [MIT](../../LICENSE)
