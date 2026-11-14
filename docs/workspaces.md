# Declarative workspaces

Schema `libtmux.lisp.workspace/1`: topology-only creation and reuse. For
logical IDs, ownership records, drift reports and explicit reconciliation, use
[owned workspaces](workspace-owned.md).

`libtmux/workspace` validates a closed workspace description, plans without
I/O, and creates a missing session through the core library.

- Reapplying an exact topology dispatches no mutations.
- A conflict fails before the first mutation.
- A later failure retains every attempted
  [`command-outcome`](api.md#command-outcome-type).

[Workspace API](workspace-api.md) · [v1 contract](design/workspace-v1.md) ·
[operation outcomes](operations.md#outcomes-and-target-checks)

## Load the optional system

The workspace system depends on core `libtmux` and the locked Jzon parser. It
does not load with core.

```lisp
(asdf:load-system "libtmux/workspace")
```

The command-line adapter is another explicit system:

```lisp
(asdf:load-system "libtmux/workspace/cli")
```

## Describe a topology

Start with native data. This function from
[`examples/workspace.lisp`](../examples/workspace.lisp) builds a declaration
without I/O.

- The session environment is inherited by later panes.
- `:command` is literal argv.
- `:shell-command` requests shell execution during apply.

<!-- example:workspacenative -->
```lisp
(defun workspace-description ()
  "Build the demo's declaration without I/O. Commands run only during apply.
APP_LABEL seeds the session environment, inherited by subsequent panes."
  (ws:make-workspace
   '(:schema "libtmux.lisp.workspace/1"
     :session
     (:name "declared" :cwd "/tmp"
      :environment #(("APP_LABEL" . "declared"))
      :windows
      #((:name "code" :index 2 :layout :tiled
         :panes #((:shell-command "test \"$APP_LABEL\" = declared && exec /bin/cat")
                  (:command #("/bin/cat"))))
        (:name "shell" :index 5
         :panes #((:command #("/bin/cat")))))))))
```
<!-- /example -->

The shipped [`examples/workspace.json`](../examples/workspace.json) describes
the same two windows and three panes. The loader never invokes the Common Lisp
reader, evaluates input, or interns external names.

```json
{
  "schema": "libtmux.lisp.workspace/1",
  "session": {
    "name": "declared",
    "cwd": "/tmp",
    "environment": {"APP_LABEL": "declared"},
    "windows": [
      {
        "name": "code",
        "index": 2,
        "layout": "tiled",
        "panes": [
          {"shell_command": "test \"$APP_LABEL\" = declared && exec /bin/cat"},
          {"command": ["/bin/cat"]}
        ]
      },
      {
        "name": "shell",
        "index": 5,
        "panes": [{"command": ["/bin/cat"]}]
      }
    ]
  }
}
```

Reading JSON:

- [`read-workspace`](workspace-api.md#read-workspace-function) requires a
  regular UTF-8 file.
- [`parse-workspace`](workspace-api.md#parse-workspace-function) accepts a
  complete string.
- Both reject duplicate and unknown members, trailing data, nulls and
  floating-point numbers.
- Both reject input over a bound on nesting, nodes, strings, windows, panes,
  argv, environment pairs or integer tokens.

For trusted in-process data,
[`make-workspace`](workspace-api.md#make-workspace-function) accepts the
equivalent closed keyword plist.

- Sequences may be vectors or finite proper lists. Retained strings and
  containers are copied.
- Session names cannot contain periods or colons, or characters tmux would
  rewrite.
- `:layout` is a keyword such as `:tiled`; JSON uses the matching string.
- Custom layouts: `(:custom text)` or JSON `{"custom": "..."}`. Tmux validates
  checksum and geometry during apply, so failure can follow completed creation.

Session `:environment`:

- Takes `(name . value)` string pairs; JSON takes a string-valued object.
- Names are unique and exclude NUL and `=`. Empty values are allowed.
- `:max-environment` bounds pairs per session (default 256).
- Values are raw tmux session values, not an exact child environment: tmux
  supplies variables such as `TMUX_PANE` and can update inherited values on
  attachment.
- Pane and window environment keys are unsupported.

See the [creation-input contract](design/workspace-v1.md#native-data).

## Plan locally, then apply explicitly

Planning against the captured graph is local. Apply captures fresh before any
mutation, then proves the final topology with another capture. This function
is from [`examples/workspace.lisp`](../examples/workspace.lisp):

<!-- example:workspaceconfig -->
```lisp
(defun apply-workspace-document (client pathname)
  "Plan and apply one bounded workspace document through explicit CLIENT.
Return the preview steps and application result as two values. Application
shares a 30-second budget; file loading and the preview precede that budget."
  (let* ((workspace (ws:read-workspace pathname))
         (snapshot (tm:fetch-snapshot client))
         (plan (ws:plan-workspace workspace snapshot)))
    (values (ws:plan-steps plan)
            (ws:apply-workspace client workspace :total-timeout 30))))
```
<!-- /example -->

The result separates the important facts:

| Question | API |
| --- | --- |
| Did this call create the session? | `result-created-p` |
| Which core commands completed? | `result-outcomes` |
| What topology passed final proof? | `result-snapshot` |
| What would an offline creation do? | `plan-steps`, then `step-action` and `step-data` |

About `result-outcomes`:

- It returns a fresh vector in dispatch order.
- Each member is the core outcome: status, phase, diagnostics, elapsed time and
  an optional replacement observation.
- Dispatched commands stay present even when later state validation fails.
- An exact second apply returns false from `result-created-p` and an empty
  outcome vector.

## Bound application time

[`apply-workspace`](workspace-api.md#apply-workspace-function) takes
`:total-timeout` in seconds, shared across its initial capture, core steps and
final verification.

- The example passes 30. Its file loading and preview happen first.
- Omit it to keep only per-operation timeouts.
- It must be a nonnegative finite real. Zero refuses the initial read.

How the budget applies:

- Each core call gets the smaller of the remaining budget and `:timeout` (or
  the client's default).
- `:output-limit` applies separately to each core operation; `:cancel-token`
  is shared.
- The budget gates admission between operations and after local planning.
- It cannot interrupt core preparation, synchronous platform calls or additive
  cleanup, so an admitted call may run or dispatch past it. It is not a hard
  caller wall-time limit.

[`workspace-deadline-exceeded`](workspace-api.md#workspace-deadline-exceeded-type)
reports expiry between calls without inventing a command outcome.

- Before the first core-step invocation, it is signalled directly. Execution
  begins with that invocation, which can itself fail before dispatch.
- Later,
  [`workspace-apply-failed`](workspace-api.md#workspace-apply-failed-type)
  retains it as the cause, with all completed outcomes.
- The failed step is the next step refused admission, or `nil` during final
  verification.
- Inspect the retained evidence before deciding what to do; nothing retries
  automatically.

## Use the CLI without an implicit server

The source checkout ships `bin/libtmux-workspace`. Validation and offline
planning do not contact tmux:

```console
$ bin/libtmux-workspace validate examples/workspace.json
```

```json
{"status":"valid","schema":"libtmux.lisp.workspace/1","session":"declared","windows":2,"panes":3}
```

```console
$ bin/libtmux-workspace plan examples/workspace.json
```

```json
{"status":"planned","steps":5,"actions":["create-session","move-window","split-pane","select-layout","create-window"]}
```

Apply requires the socket pathname. It never falls back to the default server:

```console
$ bin/libtmux-workspace apply examples/workspace.json \
  --socket-path /path/to/owned/tmux.sock
```

- `apply` prints one JSON response: whether the session was created and how
  many core outcomes were retained.
- [`libtmux.workspace.cli:main`](workspace-api.md#main-function) returns
  status 0, 1 or 2 and takes caller-owned output streams. It never quits the
  image or enters the debugger.

Failures:

- A library failure returns status 1, leaves stdout empty and writes one JSON
  error to stderr.
- The error keeps condition names, messages, causes, workspace paths and
  limits, failed-step data and every retained command outcome.
- Outcomes carry status, dispatch phase, argv, elapsed seconds and output
  bytes. An unknown exit code is omitted.
- `stdoutBytes` and `stderrBytes` are integer arrays, so invalid UTF-8
  survives.
- Observation and cleanup failures keep their own diagnostics.
- Nested details stop after eight levels and set `detailsTruncated` to true.
- Usage errors return status 2 with usage text on stderr.

Read the retained statuses and phases before recovering from a failed apply:

- An `unknown` outcome can follow a mutation that already happened.
- Successful outcomes stay successful when a later step or observation fails.

## Handle conflicts and partial application

[`plan-workspace`](workspace-api.md#plan-workspace-function) matches an existing
session by name, then proves the topology:

- The number of named window links, every declared index and each pane count
  must match exactly.
- Extra, missing, duplicate or mismatched topology signals
  `workspace-conflict`.

During creation:

- Later explicit indexes are reserved before automatic windows. Redundant
  same-index moves dispatch nothing.
- Pane creation and final order follow the declaration.
- Each split uses the pane just created and its larger captured dimension.
  Intermediate tiled layouts stop one shrinking pane from being halved
  repeatedly.
- The requested layout runs after the final pane exists.
- No delete, restart or compensating mutation runs.

Command argv, shell source, environment, cwd and layouts are creation inputs,
not inferred from later pane state. A pane that changes process or directory
never turns a matching topology into a destructive repair plan.

If a step fails, inspect the condition while preserving its uncertainty:

```lisp
(handler-case
    (ws:apply-workspace client workspace)
  (ws:workspace-apply-failed (condition)
    (list :step (let ((step (ws:failed-step condition)))
                  (and step (ws:step-action step)))
          :outcomes (map 'vector #'tm:outcome-status
                         (ws:result-outcomes condition))
          :cause (tm:error-cause condition))))
```

A final-proof failure has no failed step: every planned command already
completed. It still retains all outcomes. The workspace layer never retries or
rolls back a mutation.

## Current boundary

- Reuse checks topology by name, index and pane count, including sessions
  created outside this library.
- Version 1 keeps no canonical declaration or owned entity mapping. It has no
  logical IDs, ownership checks, drift planning or reconciliation.
- Session environment, shell source and custom layouts are creation inputs;
  reuse does not converge them.

Version 1 omits YAML, plugins, lifecycle scripts, implicit shell expansion,
deletion, process supervision, daemon startup and control-mode events. Use
explicit core operations for anything else.
