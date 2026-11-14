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

Declare an owned tmux workspace as Lisp data or bounded JSON, preview the
changes locally, then apply them through a client you pass. Needs core
`libtmux` and Jzon; core never loads it for you.

[Documentation](https://libtmux.org/en/lisp/latest/workspace/) ·
[Workspace API][api-workspace]

## Load it

Do the root [source setup](../README.md#install-from-source) first, with its
locked optional dependencies, then:

```lisp
(asdf:load-system "libtmux/workspace")
```

## Declare a workspace

### [`libtmux.workspace:make-workspace`][api-make-workspace]: windows and panes as data

Builds a declaration without contacting tmux. The
[JSON file](../examples/owned-workspace.json) is its equivalent.

This describes two windows and three panes, from the
[runnable program](../examples/owned-workspace.lisp):

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

Run the program on its own daemon:

```console
$ mise exec -- tools/lisp.sh examples/owned-workspace.lisp
```

More: [owned workspaces](../docs/workspace-owned.md) ·
[legacy schema](../docs/workspaces.md)

## Preview and apply

### [`libtmux.workspace:apply-workspace`][api-apply-workspace]: preview, then apply

[`fetch-workspace-state`][api-fetch-workspace-state] reads tmux and
[`plan-workspace`][api-plan-workspace] previews locally. `apply-workspace`
changes tmux through the client you pass.

`ws` is `libtmux.workspace` and `tm` is `libtmux`:

<!-- example:ownedapply -->
```lisp
(defun apply-owned-description (client workspace)
  "Acquire, preview and apply explicitly; return the result and its owned record."
  (let* ((state (ws:fetch-workspace-state client workspace))
         (preview (ws:plan-workspace workspace state)))
    (assert (getf (ws:plan-data preview) :publish-p))
    (let ((result (ws:apply-workspace client workspace :total-timeout 30)))
      (assert (eq :succeeded (getf (ws:result-data result) :publication-status)))
      (values result (getf (ws:result-data result) :record)))))
```
<!-- /example -->

- Changing an existing workspace needs `:reconcile t`.
- `:total-timeout` sets one budget for the whole apply.

More: [preview and apply](../docs/workspace-owned.md#acquire-preview-and-apply)

## Limits

- **A preview is not a transaction.** Apply reads fresh state, plans again and
  can stop partway. Keep [`result-outcomes`][api-result-outcomes] and the
  failure evidence.
- **No tmux I/O** in construction, parsing or preview.
- **Reconcile is narrow.** It adds, renames and changes layout or metadata. It
  keeps unrelated entities and refuses busy, unowned or invalid ownership.
- **No automatic replay.** Inspect stopped work, then decide.
- **Two schemas.** `/2` uses logical IDs and ownership records. Legacy `/1`
  reuses topology only.
- **No tmuxp documents.**
- **Argv and shell stay apart.** `:command` is literal argv; `:shell-command`
  is shell source.

[Workspace guide](../docs/workspace-owned.md) · [API][api-workspace] ·
[Ownership design](../docs/design/workspace-v2.md) ·
[CLI system](cli/README.md) · [Changelog](../CHANGELOG.md) · [MIT](../LICENSE)

[api-apply-workspace]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-apply-workspace/
[api-fetch-workspace-state]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-fetch-workspace-state/
[api-make-workspace]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-make-workspace/
[api-plan-workspace]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-plan-workspace/
[api-result-outcomes]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace-result-outcomes/
[api-workspace]: https://libtmux.org/en/lisp/latest/workspace/reference/libtmux-workspace/
