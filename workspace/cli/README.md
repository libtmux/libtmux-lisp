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

[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/lisp/latest/workspace/)

</div>

Validate workspace files, inspect ownership, preview changes and apply them to
a tmux endpoint you name. Depends only on
[`libtmux/workspace`](../README.md).

[Documentation](https://libtmux.org/en/lisp/latest/workspace/) ·
[CLI API][api-cli]

## Load it

Do the root [source setup](../../README.md#install-from-source) first, with its
locked dependencies. Run from the checkout root.

## Check a workspace file

### `tools/workspace-cli.lisp validate`: parse a file, no tmux

```console
$ mise exec -- sbcl --script tools/workspace-cli.lisp validate examples/owned-workspace.json
```

It reports `"status":"valid"`, schema `libtmux.lisp.workspace/2`, two windows
and three panes. Validation never contacts tmux.

```console
$ mise exec -- sbcl --script tools/workspace-cli.lisp
```

Prints the command grammar and exits 2. The `sbcl` launcher answers `--help`
itself, so the program has no such flag.

- `plan`, `apply` and `inspect` need `--socket-path` for owned workspaces.
- `--program` selects the tmux binary when `PATH` has the wrong one.
- `--reconcile` lets owned `plan` and `apply` change existing work. A preview
  grants no authority to apply.
- Legacy `/1` files can also preview offline, with no daemon.

Run every example, this entry point included, on a private daemon:

```console
$ mise run examples
```

More: [CLI guide](../../docs/workspace-owned.md#use-the-cli)

## Embed it

### [`libtmux.workspace.cli:main`][api-main]: an exit code, not an exit

Load the adapter:

```lisp
(asdf:load-system "libtmux/workspace/cli")
```

`main` returns the code; it does not end the Lisp image or close your streams.

- **0** success, including a completed `inspect` that finds busy or invalid
  ownership.
- **1** document or operational failure, as structured JSON on stderr with the
  command evidence.
- **2** invalid usage.
- Do not retry an uncertain `apply` automatically.

[Workspace library](../README.md) · [CLI API][api-cli] ·
[Changelog](../../CHANGELOG.md) · [MIT](../../LICENSE)

[api-cli]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-cli/
[api-main]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-cli-main/
