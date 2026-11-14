# Owned workspaces

Use `libtmux/workspace` to declare a workspace, keep logical-to-physical IDs,
and reconcile permitted changes explicitly.

- Acquisition reads tmux; planning over acquired state is local.
- Application reacquires and verifies its targets before each operation.

[Workspace API](workspace-api.md) · [System README](../workspace/README.md) ·
[Ownership protocol](design/workspace-v2.md) · [Legacy topology reuse](workspaces.md)

## Run the complete program

Complete the [source setup](../README.md#install-from-source), including locked
optional dependencies. From the checkout root:

```console
$ mise exec -- tools/lisp.sh examples/owned-workspace.lisp
```

The [program](../examples/owned-workspace.lisp):

- Owns a private daemon and closes its client and daemon on every exit.
- Ends one apply on purpose with a bad layout checksum, then inspects the
  stopped work.
- Waits on a raw notification inside its own daemon, so it runs on tmux 3.3a
  or newer. The signal does not prove a later application consumed input.
- Prints `OWNED WORKSPACE PASS` on success.

The named [`wait-for`](api.md#wait-for-function) needs tmux 3.8 or newer.

## Start with native data

Load the optional system after registering this checkout with ASDF:

```lisp
(asdf:load-system "libtmux/workspace")
```

This pure constructor, from the complete program, never contacts tmux:

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

The equivalent [JSON document](../examples/owned-workspace.json) declares the
same two windows and three panes.

- `:command` is literal argv.
- `:shell-command` explicitly requests shell source.
- Parsing never executes either.

IDs and ownership:

- The root, session, windows and panes carry bounded logical IDs.
- Names and indexes can change without replacing an ID.
- Captured tmux `$`, `@` and `%` IDs are separate physical identities.
  Application records bind them to the declaration and the observed daemon.
- Input and projected data own their mutable containers and strings.

## Acquire, preview and apply

The remaining excerpts use the package-local nicknames `tm` (`libtmux`) and
`ws` (`libtmux.workspace`).
[`fetch-workspace-state`](workspace-api.md#fetch-workspace-state-function)
acquires ready owned state or proven vacancy. This function previews locally,
then applies through the same explicit client:

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
drift, conflicts and informational context.

- `:publish-p` says whether the plan requires publication.
- An empty step vector alone is not a no-op: metadata-only changes can still
  need publication.

Preview rules:

- A preview is observational and grants no execution authority. Apply
  reacquires state and plans again.
- Apply refuses unowned sessions, invalid mappings and busy claims.
- A matching session name does not grant ownership.

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
layout. The session, window and first pane keep their physical IDs; earlier
observations keep their captured names.

Reconciliation:

- Preserves unrelated entities.
- Does not adopt an unowned session, remove extra work, steal a busy claim or
  replace existing pane processes.
- Gives existing command, working-directory and environment changes explicit
  refusals; see the [protocol](design/workspace-v2.md).
- Applies named and custom layouts through
  [`select-layout`](api.md#select-layout-function). Custom JSON layouts need
  tmux 3.8 or newer.

## Keep result and failure evidence

[`result-data`](workspace-api.md#result-data-function) returns two values:

- Owned data and `t` for schema `/2`; `nil, nil` for legacy `/1`.
- Owned data holds phase, mappings, selected/candidate/observed metadata, the
  selected record and publication status.

Related readers:

- `result-created-p` reports creation of the owned session.
- An unchanged apply still acquires state and retains its reads.
- `result-snapshot` is the replacement observation.
- `result-outcomes` lists command outcomes in chronological order.
- `result-causes` keeps the original conditions.
- All of these readers are local.
- A public
  [`workspace-apply-failed`](workspace-api.md#workspace-apply-failed-type)
  exposes the same evidence and the actual failed step where known.

Failure rules:

- Publication is the final mutation.
- A failed observation after successful publication differs from failed or
  uncertain publication.
- Do not repeat an interrupted apply automatically. Completed steps stay
  completed; an apply is not a transaction.

`:total-timeout` sets one admission budget across acquisition, planning and
application.

- Per-operation timeout and output limits keep their own meanings.
- Synchronous preparation and cleanup can extend caller wall time.

## Inspect stopped work

[`inspect-workspace`](workspace-api.md#inspect-workspace-function) acquires
diagnostic evidence even when ownership metadata is busy, incomplete or
invalid. It returns an inspection object that cannot satisfy the planning input
type:

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

- `:complete-p` means the inspection read completed.
- `:busy` describes the interrupted writer, not readiness to plan or retry.

On a terminal read failure,
[`workspace-inspection-error`](workspace-api.md#workspace-inspection-error-type)
retains partial `inspection-evidence` and a separate `inspection-terminal`.

- Inspection readers expose attempts, snapshots, outcomes and original causes,
  and perform no further I/O.
- `workspace-state-error` likewise retains partial ready-state acquisition
  evidence without inventing vacancy.

## Use the CLI

The separate `libtmux/workspace/cli` system ships
[`bin/libtmux-workspace`](../bin/libtmux-workspace). Validation is local:

```console
$ bin/libtmux-workspace validate examples/owned-workspace.json
```

Success reports schema `libtmux.lisp.workspace/2`, ID `demo-workspace`, two
windows and three panes. Show the accepted options:

```console
$ bin/libtmux-workspace --help
```

Options:

- `plan FILE`, `apply FILE` and `inspect FILE` need `--socket-path PATH` for
  owned documents.
- `--program PROGRAM` selects the native tmux executable.
- `--reconcile` is a standalone flag, for owned plan and apply only.
- Endpoint `plan` acquires state before previewing; `inspect` never mutates.
- Legacy `/1` also supports an offline creation preview with no endpoint.

Exit codes and streams:

- `0`: command completed. `2`: invalid usage. `1`: document or operational
  failure.
- Successful results use stdout; errors use stderr.
- A completed inspection exits `0` even when it reports busy or invalid
  ownership.
- A terminal failed inspection exits `1` with its retained evidence.

Owned summaries add `data`:

- Keys are lowercase native keyword names.
- `false` stays `false`; absent optional values are `null`; vectors are arrays.
- Environment and session-group associations are objects.
- Application summaries keep `commandOutcomes` and causes. Failures keep
  outcomes and failed-step data.
- Snapshots stay in the Lisp API; JSON does not expand the recursive graph.

Run the CLI end to end against an owned endpoint:

```console
$ mise run examples
```
