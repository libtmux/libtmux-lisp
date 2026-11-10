# Owned workspaces

Use `libtmux/workspace` to create a declared workspace, retain logical-to-physical
IDs, and explicitly reconcile permitted changes. Acquisition reads tmux;
planning over acquired state is local. Application reacquires and verifies its
targets before each operation.

[Workspace API](workspace-api.md) · [System README](../workspace/README.md) ·
[Ownership protocol](design/workspace-v2.md) · [Legacy topology reuse](workspaces.md)

## Run the complete program

Complete the [source setup](../README.md#install-from-source), including locked
optional dependencies. From the checkout root:

```console
$ mise exec -- tools/lisp.sh examples/owned-workspace.lisp
```

The [program](../examples/owned-workspace.lisp) owns a private daemon and closes
its client and daemon on every exit. It checks native/file equivalence, printed
shell output, environment values, identity-preserving reconciliation, no-op
reapplication, retained observations and an unrelated session. It deliberately
ends one apply with a bad layout checksum, then inspects the stopped work.
Success prints `OWNED WORKSPACE PASS`.

The program uses a bounded raw notification wait within its owned daemon to
run on tmux 3.3a through 3.8. The shell signals after printing its label; this
does not prove a later application consumed input. The named
[`wait-for`](api.md#wait-for-function) waiting contract requires tmux 3.8+.

## Start with native data

Load the optional system after registering this checkout with ASDF:

```lisp
(asdf:load-system "libtmux/workspace")
```

This pure constructor function comes from the complete program:

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

The equivalent [JSON document](../examples/owned-workspace.json) has two windows
and three panes. The example compares both declarations before binding its
run-specific notification environment. `:command` is literal argv;
`:shell-command` explicitly requests shell source. Parsing never executes either.

The root, session, windows and panes have bounded logical IDs. Names and indexes
can change without replacing those IDs. Captured tmux `$`, `@` and `%` IDs are
separate physical identities; application records bind them to the declaration
and observed daemon. Input and projected data own their mutable containers and
strings.

## Acquire, preview and apply

In the remaining function excerpts, the program declares package-local `tm`
for `libtmux` and `ws` for `libtmux.workspace`.
[`fetch-workspace-state`](workspace-api.md#fetch-workspace-state-function)
acquires ready owned state or proven vacancy. The following function previews
locally and then applies through the same explicit client:

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

The [`plan-data`](workspace-api.md#plan-data-function) plist separates changes,
drift, conflicts and informational context. `:publish-p` says whether the plan
requires publication. An empty step vector alone does not establish a no-op:
metadata-only changes can still need publication.

A preview is observational data. It grants no execution authority; apply
reacquires state and plans again. Unowned sessions, invalid mappings and busy
claims are refused. A matching session name does not grant ownership.

## Reconcile explicitly

Default application refuses declaration changes or captured drift. Pass
`:reconcile t` to preview and apply permitted additions, renames, layouts and
metadata changes:

<!-- example:ownedreconcile -->
```lisp
(defun reconcile-owned-description (client workspace)
  "Preview permitted edits, then reacquire and apply them without replacing IDs."
  (let* ((state (ws:fetch-workspace-state client workspace))
         (preview (ws:plan-workspace workspace state :reconcile t)))
    (assert (getf (ws:plan-data preview) :publish-p))
    (ws:apply-workspace client workspace :reconcile t :total-timeout 30)))
```
<!-- /example -->

The program renames the session and code window, adds a pane and changes the
layout. Assertions establish that the original session, window and first pane
retain their physical IDs. Earlier observations retain their captured names.
The unrelated session remains present.

Reconciliation preserves unrelated entities; it does not adopt an unowned
session, remove extra work, steal a busy claim or replace existing pane
processes. Existing command, working-directory and environment changes have
the explicit refusals described in the [protocol](design/workspace-v2.md).
Named layouts and custom layout descriptions use the core
[`select-layout`](api.md#select-layout-function) contract, including the live
tmux 3.8 minimum for custom JSON layouts.

## Keep result and failure evidence

[`result-data`](workspace-api.md#result-data-function) returns two values:
owned data and `t` for schema `/2`, or `nil, nil` for legacy `/1`. Owned data
retains phase, mappings, selected/candidate/observed metadata, the selected
record and publication status. `result-created-p` reports creation of the owned
session. An unchanged application still acquires state and retains its reads.

`result-snapshot` provides the replacement observation. `result-outcomes`
returns chronological command outcomes; `result-causes` retains original
conditions. These readers are local. A public
[`workspace-apply-failed`](workspace-api.md#workspace-apply-failed-type)
exposes the same evidence and the actual failed step where known.

Publication is the final mutation. Failed observation after successful
publication differs from failed or uncertain publication. Do not automatically
repeat an interrupted apply. Completed steps remain completed; an apply is
not a transaction.

Use `:total-timeout` for one admission budget across acquisition, planning and
application. Per-operation timeout and output limits retain their own meanings;
synchronous preparation and cleanup can extend caller wall time.

## Inspect stopped work

[`inspect-workspace`](workspace-api.md#inspect-workspace-function) explicitly
acquires diagnostic evidence even when ownership metadata is busy, incomplete
or invalid. It returns a distinct inspection object, which cannot satisfy the
planning input type:

<!-- example:ownedinspection -->
```lisp
(defun inspect-stopped-workspace (client workspace)
  "Acquire incomplete ownership evidence; never retry the interrupted apply."
  (let* ((inspection (ws:inspect-workspace client workspace))
         (data (ws:inspection-data inspection)))
    (assert (getf data :complete-p))
    (assert (eq :busy (getf data :status)))
    data))
```
<!-- /example -->

Here `:complete-p` means the inspection read completed. `:busy` describes the
interrupted writer, not readiness to plan or retry. The program uses a canonical
layout header with an incorrect checksum to exercise this path without
terminating its daemon.

On a terminal read failure,
[`workspace-inspection-error`](workspace-api.md#workspace-inspection-error-type)
retains partial `inspection-evidence` and a separate `inspection-terminal`.
Inspection readers expose attempts, snapshots, outcomes and original causes;
they perform no further I/O. A `workspace-state-error` similarly retains partial
ready-state acquisition evidence without inventing vacancy.

## Use the CLI

The separate `libtmux/workspace/cli` system ships
[`bin/libtmux-workspace`](../bin/libtmux-workspace). Validation is local:

```console
$ bin/libtmux-workspace validate examples/owned-workspace.json
```

Success reports schema `libtmux.lisp.workspace/2`, ID `demo-workspace`, two
windows and three panes. Inspect the accepted option grammar:

```console
$ bin/libtmux-workspace --help
```

`plan FILE`, `apply FILE` and `inspect FILE` require `--socket-path PATH` for
owned documents; `--program PROGRAM` selects the native tmux executable.
`--reconcile` is a standalone flag for owned plan/apply only. Endpoint plan
acquires state before previewing; inspect never mutates. Legacy `/1` additionally
supports an offline creation preview without an endpoint.

Exit codes are 0 for completed commands, 2 for invalid usage, and 1 for document
or operational failure. Successful results use stdout; errors use stderr.
A completed inspection exits 0 even when it reports busy or invalid ownership.
Terminal failed inspection exits 1 with its retained evidence.

Owned summaries add `data` using lowercase native keyword names. Boolean
fields preserve `false`, optional absent values use `null`, and vectors use
arrays. Environment and session-group associations are objects. Application
summaries retain `commandOutcomes` and causes; failures retain outcomes and
failed-step data. Snapshots are available through the Lisp API rather than
recursive JSON graph expansion.

`mise run examples` executes the CLI with cold compilation, creation, no-op
reapply, explicit reconcile, failure reporting and busy inspection on an owned
endpoint. `mise run package-examples` repeats these checks from the extracted
source artifact.
