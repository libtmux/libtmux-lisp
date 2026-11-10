<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="../docs/assets/logo.svg" type="image/svg+xml">
    <img src="../docs/assets/logo-512.png" width="128" height="128" alt="libtmux for Common Lisp">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# libtmux/workspace

</div>

Describe a tmux workspace with native Lisp data or bounded JSON, preview its
topology locally, then apply it through an explicit client. This optional ASDF
system consumes core `libtmux` and Jzon; core does not load it automatically.

## Load and use

Complete the root [source setup](../README.md#install-from-source), including
the locked optional dependencies, then load:

```lisp
(asdf:load-system "libtmux/workspace")
```

Start with the [native constructor](../docs/workspaces.md#describe-a-topology),
then [preview and apply](../docs/workspaces.md#plan-locally-then-apply-explicitly).
The [shipped declaration](../examples/workspace.json) and its
[native equivalent](../examples/workspace.lisp) create two windows and three
panes. The complete example compares both declarations, applies one and checks
that reapplying its exact topology dispatches no mutations.

Run it from the checkout root on an owned daemon:

```console
$ mise run examples
```

## Application boundary

Construction, parsing and preview perform no tmux I/O. Application acquires
fresh state and can partially complete; retain
[`result-outcomes`](../docs/workspace-api.md#result-outcomes-function) and
failure evidence. A preview is not an executable transaction.

The public v1 format describes topology reuse. It does not establish that
existing commands, directories, environment or layout match a declaration,
and does not accept tmuxp documents. Literal argv and explicit shell source
have separate fields. Use `:total-timeout` for a shared application budget;
per-operation timeouts and output limits retain their own meaning.

[Workspace guide](../docs/workspaces.md) · [API](../docs/workspace-api.md) ·
[v1 contract](../docs/design/workspace-v1.md) ·
[CLI system](cli/README.md) · [Changelog](../CHANGELOG.md) · [MIT](../LICENSE)
