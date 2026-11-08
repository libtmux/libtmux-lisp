# Workspace system v1

`libtmux/workspace` turns one owned, bounded workspace description into an
explicit plan and applies that plan through the core `libtmux` system. It is a
separate ASDF system: loading `libtmux` does not load a JSON parser or workspace
policy.

## Scope

Version 1 creates or reuses one named session on an explicitly supplied
[`libtmux:client`](../api.md#client-type). It manages the declared window and
pane topology. It does not terminate sessions, windows, or panes; replace
processes; run hooks; evaluate Lisp; or choose a
default tmux endpoint. It does not evaluate command data as shell source.

The public workflow is:

1. construct a workspace from native data or parse a bounded JSON document;
2. call `plan-workspace` without a snapshot for an offline creation plan, or
   with a captured snapshot for a no-op, creation plan, or conflict;
3. call `apply-workspace` with an explicit live client;
4. inspect the returned result, including every retained command outcome.

Planning and inspection perform no tmux I/O. Applying first calls
[`libtmux:fetch-snapshot`](../api.md#fetch-snapshot-function), then executes the
creation plan. It never retries a mutation.

## Native data

`make-workspace` accepts this closed plist/vector shape:

```lisp
(:schema "libtmux.lisp.workspace/1"
 :session
 (:name "demo"
  :windows
  #((:name "editor"
     :index 1
     :layout :tiled
     :panes #((:command #("/bin/cat"))
              (:cwd "/srv/app" :command #("/bin/cat")))))))
```

The root accepts only `:schema` and `:session`. A session accepts `:name`,
`:cwd`, and `:windows`. A window accepts `:name`, optional `:index`, optional
`:cwd`, optional `:layout`, and `:panes`. A pane accepts optional `:cwd` and
optional `:command`. Unknown or duplicate keys are errors.

Names are nonempty strings that tmux preserves exactly. Session names exclude
periods and colons; all names exclude NUL, control characters and backslash.
Window names must be unique. A window has at least one pane. `:index`, when
present, is a unique nonnegative integer.
Commands are nonempty finite vectors or lists of NUL-free strings. Core passes
multiple arguments directly to tmux; singleton argv uses its fixed `/bin/sh`
exec adapter, with caller text passed as positional data. CWD values are
nonempty NUL-free strings and remain strings;
the library does not reinterpret remote paths through the local filesystem.

Session CWD is the default for windows and panes. Window CWD overrides it for
that window. Pane CWD overrides both. Omitted commands use tmux's default shell.
Layout names are limited to tmux's named layouts: `even-horizontal`,
`even-vertical`, `main-horizontal`, `main-vertical`, and `tiled`.

Construction copies every retained list, vector, and string. `workspace-data`
returns another defensive copy. Mutating either input or output cannot change
the workspace.

## JSON data

`parse-workspace` accepts the equivalent complete JSON document:

```json
{
  "schema": "libtmux.lisp.workspace/1",
  "session": {
    "name": "demo",
    "windows": [
      {
        "name": "editor",
        "index": 1,
        "panes": [
          {"command": ["/bin/cat"]},
          {"cwd": "/srv/app", "command": ["/bin/cat"]}
        ]
      }
    ]
  }
}
```

The JSON grammar is closed. Duplicate and unknown members are errors. External
names are compared as strings and are not interned. Defaults bound UTF-8 input
bytes, nesting, node count, string length, windows, panes per window, total
panes, and argv length. `read-workspace` opens without blocking on special
files, validates that same descriptor is a regular file, and bounds the bytes
read. JSON null and floating-point numbers are not valid workspace values.

## Planning and reuse

An offline plan contains `:create-session`, optional `:move-window`,
`:create-window`, `:split-pane`, and optional `:select-layout` steps in execution
order. The move step gives the first window an explicit requested index because
tmux does not accept that index on `new-session`. When its index is omitted, a
move can reserve every later explicit index; those indexed windows are created
before remaining automatic windows. A move already at its destination is a
zero-command step. A plan against a snapshot behaves as follows:

- no session with the declared name: return the creation plan;
- one session with exactly the declared window names, optional indexes, and
  pane counts: return an empty no-op plan;
- any other topology: signal `workspace-conflict` before dispatch.

Tmux session names are unique, but the planner still rejects ambiguous captured
input. Window matching is by declared name. An omitted index is not governed;
an explicit index must match. Extra, missing, or duplicate windows and a pane
count mismatch are conflicts. The planner does not infer process equality from
`:pane/current-command`.

CWD, command, and named layout are creation inputs. They are not converged after
the session exists because tmux does not expose enough stable evidence to prove
their originating intent. A matching existing topology therefore produces a
no-op even if a pane later changes process or directory. Applications that need
process supervision should use explicit core operations.

## Apply and failure evidence

`apply-workspace` requires a `libtmux:client`. It fetches a snapshot, plans, and
either returns a no-op result or executes each step in order. The first window
and pane are created by `libtmux:new-session`; later windows use
`libtmux:new-window`; later panes use `libtmux:split-pane`; named layouts use
`libtmux:select-layout`. Pane creation follows declaration order. Each split
targets the pane just created and chooses its larger captured dimension; tiled
rebalancing between splits prevents repeatedly halving one shrinking pane. The
declared layout is applied once every pane exists. An omitted final layout
remains unmanaged.

Every dispatched operation's `libtmux:command-outcome` is retained in the
result, including a successful mutation whose replacement observation cannot
advance workspace execution state. If a later step fails,
`workspace-apply-failed` retains completed outcomes and the failing step. The
condition makes no rollback claim. Callers must inspect core outcome status and
dispatch phase before deciding whether a retry is safe.

After a successful creation, apply acquires one replacement snapshot and proves
that it now plans as a no-op. Failure to prove the final topology is reported;
it does not erase already completed mutations. Reapplying an exact workspace is
a zero-mutation no-op.

`apply-workspace` accepts an optional `:total-timeout` in seconds. It starts
before the initial capture, caps each core call by the smaller of remaining
time and the per-operation timeout, and checks again after initial and final
planning. Omission keeps the per-operation policy. Zero refuses even the first
read. Output limits remain per operation, and cancellation is shared.

This is an admission budget between workspace operations. Core preparation,
synchronous platform calls and additive cleanup can carry an admitted call
past it; it does not impose a hard wall-time or absolute dispatch deadline
inside core. Boundary exhaustion raises `workspace-deadline-exceeded` directly
before the first core-step invocation. That invocation begins execution and may
itself fail before dispatch. Later, `workspace-apply-failed` retains
that cause, completed outcomes and the next unstarted step, or no step during
final verification. An exhausted budget does not make completed effects
uncertain and never triggers a retry.

## Explicit exclusions

Version 1 has no YAML, plugins, lifecycle scripts, environment expansion,
arbitrary Lisp reader input, shell command strings, deletion/reordering,
automatic daemon startup, control-mode transport, or MCP integration. Those
features require separate contracts and evidence.
