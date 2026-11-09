# Declarative workspaces

`libtmux/workspace` validates a closed workspace description, produces an
inspectable plan without I/O, and creates a missing session through the core
library. Reapplying an exact topology dispatches no mutations. A conflict fails
before the first mutation; a later failure retains every attempted
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
[`examples/workspace.lisp`](../examples/workspace.lisp) constructs an owned
declaration without I/O. The session environment is inherited by later panes.
`:command` is literal argv; `:shell-command` explicitly requests shell execution
during apply.

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
the same two windows and three panes. The tested examples compare the native
and JSON declarations before applying them. The loader never invokes the Common
Lisp reader, evaluates input, or interns external names.

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

[`read-workspace`](workspace-api.md#read-workspace-function) requires a regular
UTF-8 file. [`parse-workspace`](workspace-api.md#parse-workspace-function)
accepts a complete string. Both reject duplicate and unknown members, trailing
data, nulls, floating-point numbers, and exhausted input, nesting, node, string,
window, pane, argv, environment-pair, or integer-token bounds.

For trusted in-process data, [`make-workspace`](workspace-api.md#make-workspace-function)
accepts the equivalent closed keyword plist with vectors or finite proper
lists. It copies retained strings and containers. Session names cannot contain
periods or colons; names also reject characters tmux would rewrite. `:layout`
uses a Common Lisp keyword such as `:tiled`; JSON uses the corresponding string.
Custom layouts use `(:custom text)` or JSON `{"custom": "..."}`. Tmux validates
their checksum and geometry during apply; failure can follow completed creation.

Session `:environment` accepts `(name . value)` string pairs; JSON accepts a
string-valued object. Names are unique and exclude NUL and `=`. Empty values
are allowed. `:max-environment` defaults to 256 and bounds pairs per session.
These are raw tmux session values, not an exact child environment; tmux supplies
variables such as `TMUX_PANE` and can update inherited values on attachment.
Pane/window environment keys are unsupported. See the
[creation-input contract](design/workspace-v1.md#native-data).

## Plan locally, then apply explicitly

This function is executable source from
[`examples/workspace.lisp`](../examples/workspace.lisp). Planning against the
captured graph is local. Applying performs its own fresh capture before any
mutation, then proves the final topology with another capture.

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

`result-outcomes` returns a fresh vector in dispatch order. Each member is the
core outcome with status, phase, diagnostics, elapsed time, and optional
replacement observation. Successfully dispatched commands remain present even
when later workspace state validation fails. An exact second apply returns false from
`result-created-p` and an empty outcome vector.

## Bound application time

[`apply-workspace`](workspace-api.md#apply-workspace-function) accepts
`:total-timeout` in seconds, shared across its initial capture, core steps and
final verification. The example supplies 30 seconds for application; its file
loading and preview happen first. Omit the argument to keep only per-operation
timeouts. An explicit value must be a nonnegative finite real; zero refuses
the initial read.

Each core call receives the smaller of the remaining application budget and
`:timeout` or the client's default. `:output-limit` still applies separately to
each core operation, and `:cancel-token` is shared. The application budget
checks admission between operations and after local planning. It cannot
interrupt core preparation, synchronous platform calls or additive cleanup;
an admitted call may run or dispatch past it. It is not a hard caller wall-time
limit.

[`workspace-deadline-exceeded`](workspace-api.md#workspace-deadline-exceeded-type)
reports expiry between calls without inventing a command outcome. Before the
first core-step invocation it is signalled directly. Execution begins with that
invocation, which can itself fail before dispatch. Later,
[`workspace-apply-failed`](workspace-api.md#workspace-apply-failed-type)
retains it as the cause with all completed outcomes. The failed step is the
next step refused admission, or `nil` during final verification. Inspect the
retained evidence before deciding what to do next; no automatic retry occurs.

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

The single JSON response reports whether the session was created and how many
core outcomes were retained. The tested
[`libtmux.workspace.cli:main`](workspace-api.md#main-function) function returns
status 0, 1, or 2 and accepts caller-owned output streams; it does not quit the
image or enter the debugger.

Library failures return status 1, leave stdout empty, and write one JSON error
to stderr. It retains condition names, messages, causes, workspace paths and
limits, failed-step data, and every retained command outcome. Outcomes include
status, dispatch phase, argv, elapsed seconds and output bytes; an unknown exit
code is omitted. `stdoutBytes` and `stderrBytes` are integer arrays, preserving
invalid UTF-8. Observation and cleanup failures retain their own diagnostics.
Nested details stop after eight levels and set `detailsTruncated` to true.
Usage errors return status 2 with usage text on stderr.

Inspect retained statuses and phases before recovering from a failed apply.
An `unknown` outcome can follow a mutation that already happened. Successful
outcomes remain successful when a later step or observation fails.

## Handle conflicts and partial application

[`plan-workspace`](workspace-api.md#plan-workspace-function) matches an existing
session by name, then proves the exact number of named window links, every
declared index, and each pane count. Extra, missing, duplicate, or mismatched
topology signals `workspace-conflict`. During creation, later explicit indexes
are reserved before automatic windows, and redundant same-index moves dispatch
nothing. Pane creation and final order follow the declaration. Each split uses
the pane just created and its larger captured dimension; intermediate tiled
layouts prevent repeatedly halving one shrinking pane. The requested layout
runs after the final pane exists. No delete, restart, or compensating mutation
runs.

Command argv, explicit shell source, environment, cwd and layouts are creation
inputs. They are not inferred
from later pane state. A pane may change process or directory without turning an
otherwise matching topology into a destructive repair plan.

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

A final-proof failure has no failed step because every planned command already
completed. It still retains all outcomes. The workspace layer never retries or
rolls back a mutation.

## Current boundary

Reuse checks topology by name, index and pane count, including sessions created
outside this library. Version 1 does not retain a canonical declaration or
owned entity mapping. Logical IDs, ownership checks, declaration-versus-drift
planning and explicit reconciliation remain unfinished. Session environment,
shell source and custom layouts are creation inputs; reuse does not converge
them.

Version 1 omits YAML, plugins, lifecycle scripts, implicit shell expansion,
deletion, process supervision, daemon startup and control-mode events.
Use explicit core operations when the application
needs behavior outside this bounded bootstrap/reuse contract.

The FiveAM suite proves pure planning and parser bounds without tmux. Integration
tests apply and reapply the same document on owned exact tmux 3.3a and 3.8
servers. `mise run package-examples` repeats the executable example from the
source archive.
