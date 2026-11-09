# Workspace API

Generated from live package documentation and signatures by `mise run docs`.
Edit source docstrings; `mise run check` detects drift.

[Workspace guide](workspaces.md) · [Core API](api.md) · [Transport](transport.md)

Owned Common Lisp workspace descriptions and explicit tmux application.
MAKE-WORKSPACE validates inert native data without evaluation. PLAN-WORKSPACE
is local and pure; APPLY-WORKSPACE is the explicit external-operation boundary.
Workspace objects, plans, steps, results, and their readers return defensive
data. Conflicts fail before mutation, and partial application retains evidence.

## Functions

<a id="apply-workspace-function"></a>

### apply-workspace

`(apply-workspace client workspace &key cancel-token (timeout nil timeout-p) (output-limit nil output-limit-p) (total-timeout nil total-timeout-p))`

Create or reuse WORKSPACE through explicit CLIENT and return WORKSPACE-RESULT.
The function first calls FETCH-SNAPSHOT and PLAN-WORKSPACE. A proven match
returns immediately with no command outcomes. A missing session executes each
planned core mutation once, in order, then captures and proves the final
topology. TIMEOUT and OUTPUT-LIMIT, when supplied, apply separately to each core
operation; CANCEL-TOKEN is shared. Conflicts dispatch no mutation.

TOTAL-TIMEOUT, when supplied, is a nonnegative finite number of seconds shared
across the application. Each acquisition and core step receives the smaller of
its remaining total budget and TIMEOUT or the client's default. The budget is
also checked after initial and final planning. Zero refuses the initial read;
omission adds no application budget. OUTPUT-LIMIT remains per operation.

This budget controls admission at workspace boundaries. Preparation before a
core timer starts, synchronous platform calls and additive cleanup can let an
admitted core call run or dispatch past it; caller wall time is not bounded.
Boundary expiry before the first core-step invocation signals
WORKSPACE-DEADLINE-EXCEEDED directly. Execution begins with that invocation,
which can itself fail before dispatch. Later expiry becomes WORKSPACE-APPLY-FAILED's cause,
retaining completed outcomes. It does not imply an uncertain command effect.

Failure within a core step or later signals WORKSPACE-APPLY-FAILED. RESULT-OUTCOMES retains
every dispatched outcome, including one whose post-command observation cannot
advance workspace state; FAILED-STEP identifies the failed or unstarted next
step. Final-verification failure has no failed step. No rollback or automatic
retry occurs.


See also: [failed-step](#failed-step-function), [plan-workspace](#plan-workspace-function), [result-outcomes](#result-outcomes-function), [result-snapshot](#result-snapshot-function), [workspace-deadline-exceeded](#workspace-deadline-exceeded-type).

[Source](../src/workspace.lisp)

<a id="failed-step-function"></a>

### failed-step

`(failed-step condition)`

Return the failed or refused next WORKSPACE-STEP, or NIL for final verification.
NIL does not imply that no mutations completed; inspect RESULT-OUTCOMES.


See also: [apply-workspace](#apply-workspace-function), [result-outcomes](#result-outcomes-function).

[Source](../src/workspace.lisp)

<a id="make-workspace-function"></a>

### make-workspace

`(make-workspace data &key (max-windows 100) (max-panes 1000) (max-argv 256) (max-environment 256))`

Validate closed native DATA and return an owned WORKSPACE without I/O.
DATA is a keyword plist in schema libtmux.lisp.workspace/1. Lists and vectors
must be finite. MAX-WINDOWS, MAX-PANES, and MAX-ARGV bound retained topology and
commands. MAX-ENVIRONMENT bounds session (name . value) string pairs; tmux
stores them in the session environment inherited by later panes. Pane :COMMAND
is argv; :SHELL-COMMAND is explicit shell source, mutually exclusive with argv.
Window :LAYOUT is a named keyword or (:CUSTOM string) validated by tmux on apply.
Names reject characters tmux would rewrite. Unknown/duplicate keys, invalid
types or limits signal INVALID-WORKSPACE. Mutable inputs are copied.


See also: [libtmux:new-session](api.md#new-session-function), [parse-workspace](#parse-workspace-function), [plan-workspace](#plan-workspace-function), [libtmux:select-layout](api.md#select-layout-function), [workspace-data](#workspace-data-function).

[Source](../src/workspace.lisp)

<a id="parse-workspace-function"></a>

### parse-workspace

`(parse-workspace source &key (max-input-bytes +default-max-input-bytes+) (max-depth +default-max-depth+) (max-nodes +default-max-nodes+) (max-string-length +default-max-string-length+) (max-windows +default-max-windows+) (max-panes +default-max-panes+) (max-argv +default-max-argv+) (max-environment +default-max-environment+) (max-integer-digits +default-max-integer-digits+))`

Parse one bounded libtmux.lisp.workspace/1 JSON string into a WORKSPACE.
The complete document uses a closed grammar, rejects duplicate members, and
never interns or evaluates external names. Limits bound UTF-8 bytes, nesting,
nodes, strings, windows, total panes, argv length, session environment pairs
(MAX-ENVIRONMENT, default 256), and integer token digits. Pane shell_command is
explicit shell source; window layout accepts a named string or a custom object.
Input and retained values are copied. Signals INVALID-WORKSPACE-DOCUMENT or
WORKSPACE-LIMIT-EXCEEDED with WORKSPACE-PATH and WORKSPACE-LIMIT diagnostics.


See also: [make-workspace](#make-workspace-function), [read-workspace](#read-workspace-function), [workspace-data](#workspace-data-function).

[Source](../src/workspace.lisp)

<a id="plan-steps-function"></a>

### plan-steps

`(plan-steps plan)`

Return PLAN's ordered steps as a fresh simple vector. No I/O.


See also: [plan-workspace](#plan-workspace-function), [step-action](#step-action-function), [step-data](#step-data-function).

[Source](../src/workspace.lisp)

<a id="plan-workspace-function"></a>

### plan-workspace

`(plan-workspace workspace &optional snapshot)`

Return a finite local WORKSPACE-PLAN, optionally against captured SNAPSHOT.
Without SNAPSHOT, return the deterministic creation plan. With SNAPSHOT, return
that plan when the named session is absent, an empty proven no-op when topology
matches, or signal WORKSPACE-CONFLICT before dispatch. Planning compares window
names, declared indexes, and pane counts; creation-only cwd, argv, and layout
are not inferred from mutable live state. Explicit indexes are reserved before
automatic windows. Pane creation and final order follow the declaration. No
tmux I/O occurs.


See also: [apply-workspace](#apply-workspace-function), [plan-steps](#plan-steps-function), [workspace-data](#workspace-data-function).

[Source](../src/workspace.lisp)

<a id="read-workspace-function"></a>

### read-workspace

`(read-workspace path &rest options &key (max-input-bytes +default-max-input-bytes+) &allow-other-keys)`

Read one bounded regular UTF-8 JSON file and return an owned WORKSPACE.
PATH is opened for input and never modified. MAX-INPUT-BYTES is enforced on
bytes read even if the file changes after opening. The descriptor is opened
nonblocking, then directories and special files are rejected before reading.
Other OPTIONS are forwarded to PARSE-WORKSPACE. Signals
INVALID-WORKSPACE-DOCUMENT or WORKSPACE-LIMIT-EXCEEDED and closes the stream.


See also: [parse-workspace](#parse-workspace-function), [workspace-data](#workspace-data-function).

[Source](../src/workspace.lisp)

<a id="result-created-p-function"></a>

### result-created-p

`(result-created-p result)`

Return true when APPLY-WORKSPACE created the declared session.


See also: [apply-workspace](#apply-workspace-function), [result-outcomes](#result-outcomes-function), [result-snapshot](#result-snapshot-function).

[Source](../src/workspace.lisp)

<a id="result-outcomes-function"></a>

### result-outcomes

`(result-outcomes result)`

Return retained COMMAND-OUTCOME objects in a fresh simple vector.


See also: [failed-step](#failed-step-function), [result-created-p](#result-created-p-function), [result-snapshot](#result-snapshot-function).

[Source](../src/workspace.lisp)

<a id="result-snapshot-function"></a>

### result-snapshot

`(result-snapshot result)`

Return the final captured SNAPSHOT retained by RESULT. No I/O.


See also: [apply-workspace](#apply-workspace-function), [result-created-p](#result-created-p-function), [result-outcomes](#result-outcomes-function).

[Source](../src/workspace.lisp)

<a id="step-action-function"></a>

### step-action

`(step-action step)`

Return STEP's action keyword, without I/O.


See also: [plan-steps](#plan-steps-function), [step-data](#step-data-function).

[Source](../src/workspace.lisp)

<a id="step-data-function"></a>

### step-data

`(step-data step)`

Return a fresh plist of STEP operands, without I/O.


See also: [plan-steps](#plan-steps-function), [step-action](#step-action-function).

[Source](../src/workspace.lisp)

<a id="workspace-data-function"></a>

### workspace-data

`(workspace-data workspace)`

Return fresh closed native data for WORKSPACE, without I/O.


See also: [make-workspace](#make-workspace-function), [plan-workspace](#plan-workspace-function).

[Source](../src/workspace.lisp)

<a id="workspace-limit-function"></a>

### workspace-limit

`(workspace-limit condition)`

Return the exhausted workspace limit name, or NIL, without I/O.

[Source](../src/workspace.lisp)

<a id="workspace-path-function"></a>

### workspace-path

`(workspace-path condition)`

Return a fresh vector locating the workspace error, without I/O.

[Source](../src/workspace.lisp)

## Classes and conditions

These objects retain owned configuration, plans, results, or bounded diagnostics.

<a id="invalid-workspace-type"></a>

### invalid-workspace

Native workspace data violates the closed workspace grammar.

[Source](../src/workspace.lisp)

Direct supertypes: `workspace-error`.

<a id="invalid-workspace-document-type"></a>

### invalid-workspace-document

A workspace JSON document is malformed, unknown, or invalid.

[Source](../src/workspace.lisp)

Direct supertypes: `invalid-workspace`.

<a id="workspace-type"></a>

### workspace

An immutable-by-contract, owned workspace description.

[Source](../src/workspace.lisp)

Direct supertypes: `standard-object`.

<a id="workspace-apply-failed-type"></a>

### workspace-apply-failed

Workspace application stopped with retained partial outcomes.

[Source](../src/workspace.lisp)

Direct supertypes: `workspace-error`.

<a id="workspace-conflict-type"></a>

### workspace-conflict

Captured topology conflicts with the declared workspace.

[Source](../src/workspace.lisp)

Direct supertypes: `workspace-error`.

<a id="workspace-deadline-exceeded-type"></a>

### workspace-deadline-exceeded

The application budget expired at a workspace boundary.
WORKSPACE-LIMIT returns :TOTAL-TIMEOUT. No new command outcome is implied;
previous completed outcomes remain on a wrapping WORKSPACE-APPLY-FAILED.
An already admitted core call retains its own timeout and cleanup contract.


See also: [apply-workspace](#apply-workspace-function), [result-outcomes](#result-outcomes-function), [workspace-limit](#workspace-limit-function).

[Source](../src/workspace.lisp)

Direct supertypes: `workspace-error`.

<a id="workspace-error-type"></a>

### workspace-error

A workspace validation, planning, or application failure.

[Source](../src/workspace.lisp)

Direct supertypes: `libtmux-error`.

<a id="workspace-limit-exceeded-type"></a>

### workspace-limit-exceeded

A workspace JSON or file input exceeds a configured bound.

[Source](../src/workspace.lisp)

Direct supertypes: `invalid-workspace-document`.

<a id="workspace-plan-type"></a>

### workspace-plan

A finite local plan; an empty step vector is a proven no-op.

[Source](../src/workspace.lisp)

Direct supertypes: `standard-object`.

<a id="workspace-result-type"></a>

### workspace-result

Retained workspace application evidence and final captured topology.

[Source](../src/workspace.lisp)

Direct supertypes: `standard-object`.

<a id="workspace-step-type"></a>

### workspace-step

One inspectable, inert workspace operation in execution order.

[Source](../src/workspace.lisp)

Direct supertypes: `standard-object`.

## Command-line adapter

The separate `libtmux/workspace/cli` system exports one testable entry point. See [read-workspace](#read-workspace-function), [plan-workspace](#plan-workspace-function), and [apply-workspace](#apply-workspace-function).

<a id="main-function"></a>

### main

`(main &key (arguments (command-line-arguments)) (stdout *standard-output*) (stderr *error-output*))`

Run the workspace CLI for ARGUMENTS and return process status 0, 1, or 2.
VALIDATE and PLAN parse one bounded file without tmux I/O. APPLY requires
--socket-path and optionally accepts --program; it scopes and closes its own
client without terminating the server. STDOUT receives one JSON result or help.
STDERR receives usage text or one JSON error retaining condition causes, failed
step data, and command outcomes, including byte arrays and unknown dispatch
status. An unavailable exit code or failed step is omitted. MAIN does not call
UIOP:QUIT, close caller streams, or enter the debugger.
Nested diagnostic details stop after eight levels and mark detailsTruncated.


See also: [apply-workspace](#apply-workspace-function), [libtmux:outcome-phase](api.md#outcome-phase-function), [libtmux:outcome-status](api.md#outcome-status-function).

[Source](../src/workspace-cli.lisp)
