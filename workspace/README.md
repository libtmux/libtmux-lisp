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

Describe an owned tmux workspace with native Lisp data or bounded JSON, preview
changes and drift locally, then apply through an explicit client. This optional ASDF
system consumes core `libtmux` and Jzon; core does not load it automatically.

## Load and use

Complete the root [source setup](../README.md#install-from-source), including
the locked optional dependencies, then load:

```lisp
(asdf:load-system "libtmux/workspace")
```

Start with the [native constructor](../docs/workspace-owned.md#start-with-native-data),
then [preview and apply](../docs/workspace-owned.md#acquire-preview-and-apply).
The [shipped declaration](../examples/owned-workspace.json) and its
[native equivalent](../examples/owned-workspace.lisp) create two windows and three
panes. The complete program checks native/file equivalence, printed output,
reconciliation with stable physical IDs, no-op reapplication and explicit
stopped-work inspection.

Run it from the checkout root on an owned daemon:

```console
$ mise exec -- tools/lisp.sh examples/owned-workspace.lisp
```

## Application boundary

Construction, parsing and preview perform no tmux I/O. Application acquires
fresh state and can partially complete; retain
[`result-outcomes`](../docs/workspace-api.md#result-outcomes-function) and
failure evidence. A preview is not an executable transaction.

Schema `/2` uses logical IDs and durable ownership records; `:reconcile t`
permits qualified additions, renames, layout and metadata changes. It preserves
unrelated entities and refuses busy, unowned or invalid ownership. Inspect
stopped work explicitly; never replay an uncertain apply automatically.

Legacy `/1` retains [topology-only reuse](../docs/workspaces.md). Neither schema
accepts tmuxp documents. Literal argv and explicit shell source have separate
fields. Use `:total-timeout` for a shared application budget; per-operation
timeouts and output limits retain their own meaning.

[Workspace guide](../docs/workspace-owned.md) · [API](../docs/workspace-api.md) ·
[Ownership contract](../docs/design/workspace-v2.md) ·
[CLI system](cli/README.md) · [Changelog](../CHANGELOG.md) · [MIT](../LICENSE)
