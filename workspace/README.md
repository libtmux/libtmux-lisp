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

[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/lisp/latest/workspace/)

</div>

Describe an owned tmux workspace with native Lisp data or bounded JSON, preview
changes and drift locally, then apply through an explicit client. This optional ASDF
system consumes core `libtmux` and Jzon; core does not load it automatically.

[Documentation](https://libtmux.org/en/lisp/latest/workspace/) ·
[Workspace API][api-workspace]

## Load and use

Complete the root [source setup](../README.md#install-from-source), including
the locked optional dependencies, then load:

```lisp
(asdf:load-system "libtmux/workspace")
```

[`libtmux.workspace:make-workspace`][api-make-workspace] constructs a declaration
without contacting tmux. This complete function from the
[runnable example](../examples/owned-workspace.lisp) describes two windows and
three panes:

<!-- example:owneddeclaration -->
```lisp
(defun owned-description ()
  "Describe two windows and three panes without contacting tmux."
  (libtmux.workspace:make-workspace
   '(:schema "libtmux.lisp.workspace/2" :id "demo-workspace"
     :session
     (:id "main" :name "owned-demo"
      :environment #(("DEMO_LABEL" . "hello from Common Lisp"))
      :windows
      #((:id "code" :name "code" :index 2 :layout :tiled
         :panes #((:id "shell" :command #("/bin/cat"))
                  (:id "repl" :command #("/bin/cat"))))
        (:id "logs" :name "logs" :index 5
         :panes #((:id "tail" :command #("/bin/cat")))))))))
```
<!-- /example -->

[`libtmux.workspace:fetch-workspace-state`][api-fetch-workspace-state] acquires
state; [`libtmux.workspace:plan-workspace`][api-plan-workspace] previews changes
locally; [`libtmux.workspace:apply-workspace`][api-apply-workspace] applies them
through an explicit client. Follow
[preview and apply](../docs/workspace-owned.md#acquire-preview-and-apply).
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
[`libtmux.workspace:result-outcomes`][api-result-outcomes] and
failure evidence. A preview is not an executable transaction.

Schema `/2` uses logical IDs and durable ownership records; `:reconcile t`
permits qualified additions, renames, layout and metadata changes. It preserves
unrelated entities and refuses busy, unowned or invalid ownership. Inspect
stopped work explicitly; never replay an uncertain apply automatically.

Legacy `/1` retains [topology-only reuse](../docs/workspaces.md). Neither schema
accepts tmuxp documents. Literal argv and explicit shell source have separate
fields. Use `:total-timeout` for a shared application budget; per-operation
timeouts and output limits retain their own meaning.

[Workspace guide](../docs/workspace-owned.md) · [API][api-workspace] ·
[Ownership contract](../docs/design/workspace-v2.md) ·
[CLI system](cli/README.md) · [Changelog](../CHANGELOG.md) · [MIT](../LICENSE)

[api-apply-workspace]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-apply-workspace/
[api-fetch-workspace-state]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-fetch-workspace-state/
[api-make-workspace]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-make-workspace/
[api-plan-workspace]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-plan-workspace/
[api-result-outcomes]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-result-outcomes/
[api-workspace]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace/
