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

`(apply-workspace client workspace &key cancel-token (timeout nil timeout-p) (output-limit nil output-limit-p) (total-timeout nil total-timeout-p) reconcile)`

Apply WORKSPACE through explicit CLIENT and return a WORKSPACE-RESULT.
Workspace/1 retains topology-only creation/reuse. Workspace/2 freshly acquires
owned state and replans; a preview is never mutation authority. By default
owned declaration changes or drift are refused; :RECONCILE permits only the
qualified additive, rename, metadata and layout changes. It never adopts an
unowned session or repeats an uncertain mutation. RECONCILE requires schema /2.

TIMEOUT and OUTPUT-LIMIT apply per core operation; CANCEL-TOKEN is shared.
TOTAL-TIMEOUT, when supplied, is a nonnegative finite number of seconds shared
across acquisition, planning and application. It controls admission, including
no-op planning, and is not a hard caller wall-time bound. Synchronous setup and
cleanup can extend an admitted call. Invalid arguments fail before application.

Owned results retain read outcomes even for no-mutation reapplication.
RESULT-DATA separates selected/candidate/observed metadata and publication
status; RESULT-CREATED-P reports creation of the owned session. Conditional
publication is the final mutation, and later observation is read-only.

Owned acquisition, planning and execution failures signal WORKSPACE-APPLY-FAILED
with local RESULT-DATA, RESULT-SNAPSHOT, RESULT-OUTCOMES and RESULT-CAUSES.
FAILED-STEP retains the actual step where known. Successful publication with
failed observation remains distinguishable from failed/uncertain publication.
Legacy failures retain their original early-validation and partial-outcome
behavior. No rollback, hidden refresh during inspection or automatic retry.


See also: [failed-step](#failed-step-function), [fetch-workspace-state](#fetch-workspace-state-function), [plan-workspace](#plan-workspace-function), [result-causes](#result-causes-function), [result-data](#result-data-function), [result-outcomes](#result-outcomes-function), [result-snapshot](#result-snapshot-function), [workspace-deadline-exceeded](#workspace-deadline-exceeded-type).

[Source](../src/workspace-api.lisp)

<a id="failed-step-function"></a>

### failed-step

`(failed-step condition)`

Return the failed or refused next WORKSPACE-STEP, or NIL for final verification.
NIL does not imply that no mutations completed; inspect RESULT-OUTCOMES.


See also: [apply-workspace](#apply-workspace-function), [result-outcomes](#result-outcomes-function).

[Source](../src/workspace.lisp)

<a id="fetch-workspace-state-function"></a>

### fetch-workspace-state

`(fetch-workspace-state client workspace &key cancel-token (timeout (slot-value client (quote timeout))) (output-limit (slot-value client (quote output-limit))) (record-limit 100000))`

Acquire ready/vacant owned metadata and a captured graph explicitly through CLIENT.
WORKSPACE must use schema /2; /1 is refused before I/O. TIMEOUT and OUTPUT-LIMIT
share the bounded read policy across attempts. RECORD-LIMIT is an integer from
1 through 100000; CANCEL-TOKEN is shared. No mutation occurs. Returns a
WORKSPACE-STATE for local planning, usable after client close. Actual read
failures signal WORKSPACE-STATE-ERROR with partial evidence; invalid arguments
remain validation failures. Failure is never reported as vacancy.


See also: [inspect-workspace](#inspect-workspace-function), [plan-workspace](#plan-workspace-function), [state-causes](#state-causes-function), [state-data](#state-data-function), [state-outcomes](#state-outcomes-function), [state-snapshot](#state-snapshot-function).

[Source](../src/workspace-api.lisp)

<a id="inspect-workspace-function"></a>

### inspect-workspace

`(inspect-workspace client workspace &key cancel-token (timeout (slot-value client (quote timeout))) (output-limit (slot-value client (quote output-limit))) (record-limit 100000))`

Acquire explicit incomplete-workspace evidence through CLIENT without mutation.
WORKSPACE must use schema /2; /1 is refused before I/O. Read limits and
CANCEL-TOKEN have FETCH-WORKSPACE-STATE's meanings. Returns a distinct
WORKSPACE-INSPECTION, never a planning input. Completed inspection can describe
BUSY or invalid ownership. A terminal failure signals WORKSPACE-INSPECTION-ERROR
with a partial inspection and original/terminal causes separately retained.


See also: [inspection-causes](#inspection-causes-function), [inspection-data](#inspection-data-function), [inspection-evidence](#inspection-evidence-function), [inspection-outcomes](#inspection-outcomes-function), [inspection-snapshots](#inspection-snapshots-function), [inspection-terminal](#inspection-terminal-function).

[Source](../src/workspace-api.lisp)

<a id="inspection-causes-function"></a>

### inspection-causes

`(inspection-causes inspection)`

Return original retained conditions in a fresh simple vector. No I/O.


See also: [libtmux:error-cause](api.md#error-cause-function), [inspection-data](#inspection-data-function), [inspection-terminal](#inspection-terminal-function).

[Source](../src/workspace-api.lisp)

<a id="inspection-data-function"></a>

### inspection-data

`(inspection-data inspection)`

Return fresh attempts, record roles and diagnostics from INSPECTION. No I/O.
Read completion does not establish valid ownership or application success.


See also: [inspect-workspace](#inspect-workspace-function), [inspection-causes](#inspection-causes-function), [inspection-snapshots](#inspection-snapshots-function).

[Source](../src/workspace-api.lisp)

<a id="inspection-evidence-function"></a>

### inspection-evidence

`(inspection-evidence condition)`

Return the partial WORKSPACE-INSPECTION retained by CONDITION. No I/O.


See also: [inspection-data](#inspection-data-function), [inspection-terminal](#inspection-terminal-function), [workspace-inspection-error](#workspace-inspection-error-type).

[Source](../src/workspace-api.lisp)

<a id="inspection-outcomes-function"></a>

### inspection-outcomes

`(inspection-outcomes inspection)`

Return INSPECTION's read outcomes in a fresh simple vector. No I/O.


See also: [inspection-data](#inspection-data-function), [libtmux:outcome-status](api.md#outcome-status-function).

[Source](../src/workspace-api.lisp)

<a id="inspection-snapshots-function"></a>

### inspection-snapshots

`(inspection-snapshots inspection)`

Return retained captured SNAPSHOT objects in a fresh simple vector. No I/O.
Each capture remains paired with its attempt's metadata in INSPECTION-DATA.


See also: [inspection-data](#inspection-data-function), [inspection-outcomes](#inspection-outcomes-function).

[Source](../src/workspace-api.lisp)

<a id="inspection-terminal-function"></a>

### inspection-terminal

`(inspection-terminal condition)`

Return the terminal condition that stopped inspection. No I/O.
The original metadata cause remains in the cause chain and inspection evidence.


See also: [libtmux:error-cause](api.md#error-cause-function), [inspection-causes](#inspection-causes-function), [inspection-evidence](#inspection-evidence-function).

[Source](../src/workspace-api.lisp)

<a id="make-workspace-function"></a>

### make-workspace

`(make-workspace data &key (max-windows 100) (max-panes 1000) (max-argv 256) (max-environment 256))`

Validate inert native DATA and return an owned WORKSPACE without I/O.
DATA is a finite keyword plist declaring libtmux.lisp.workspace/1 or /2.
Workspace/1 describes name-based topology reuse. Workspace/2 requires stable
IDs at the root, session, windows and panes; duplicate window names are allowed.
Mutable inputs are copied. Unknown/duplicate keys, cyclic containers and invalid
values signal INVALID-WORKSPACE with WORKSPACE-PATH and WORKSPACE-LIMIT.

MAX-WINDOWS, MAX-PANES, MAX-ARGV and MAX-ENVIRONMENT limit topology, individual
argv vectors and session environment pairs. Owned protocol ceilings remain in
force when a caller chooses larger limits. :COMMAND is literal argv;
:SHELL-COMMAND is explicit shell source. Cwd, environment and named/custom
layouts retain their creation meanings; changing existing processes is refused.


See also: [apply-workspace](#apply-workspace-function), [libtmux:new-session](api.md#new-session-function), [parse-workspace](#parse-workspace-function), [plan-workspace](#plan-workspace-function), [read-workspace](#read-workspace-function), [workspace-data](#workspace-data-function).

[Source](../src/workspace-api.lisp)

<a id="parse-workspace-function"></a>

### parse-workspace

`(parse-workspace source &key (max-input-bytes +default-max-input-bytes+) (max-depth +default-max-depth+) (max-nodes +default-max-nodes+) (max-string-length +default-max-string-length+) (max-windows +default-max-windows+) (max-panes +default-max-panes+) (max-argv +default-max-argv+) (max-environment +default-max-environment+) (max-integer-digits +default-max-integer-digits+))`

Parse one bounded workspace/1 or workspace/2 JSON string into a WORKSPACE.
The declared schema selects a closed grammar. Unknown/duplicate members,
invalid values and incomplete input fail; no external names are interned or
evaluated. Limits bound UTF-8 bytes, nesting, nodes, string length, topology,
argv length, session environment pairs and integer token digits. Owned protocol
ceilings remain in force when callers choose larger limits.

Workspace/2 requires stable IDs and permits repeated window names. Command
arrays are literal argv; shell_command is explicit source. Named/custom layouts
and all other creation inputs have the same meanings as MAKE-WORKSPACE.
Retained strings and containers are owned. Signals INVALID-WORKSPACE-DOCUMENT
or WORKSPACE-LIMIT-EXCEEDED with WORKSPACE-PATH and WORKSPACE-LIMIT. No tmux I/O.


See also: [make-workspace](#make-workspace-function), [read-workspace](#read-workspace-function), [workspace-data](#workspace-data-function).

[Source](../src/workspace-api.lisp)

<a id="plan-data-function"></a>

### plan-data

`(plan-data plan)`

Return (values fresh-owned-data T), or (values NIL NIL) for legacy evidence.
Accepts WORKSPACE-PLAN or WORKSPACE-CONFLICT. Owned data separates declaration
changes, captured drift, informational context, conflicts and :PUBLISH-P.
An empty step vector can still require metadata publication. No I/O.


See also: [plan-steps](#plan-steps-function), [plan-workspace](#plan-workspace-function), [workspace-conflict](#workspace-conflict-type).

[Source](../src/workspace-api.lisp)

<a id="plan-steps-function"></a>

### plan-steps

`(plan-steps plan)`

Return PLAN's ordered steps as a fresh simple vector. No I/O.
An owned plan with no domain steps can still require metadata publication.


See also: [plan-data](#plan-data-function), [plan-workspace](#plan-workspace-function), [step-action](#step-action-function), [step-data](#step-data-function).

[Source](../src/workspace.lisp)

<a id="plan-workspace-function"></a>

### plan-workspace

`(plan-workspace workspace &optional observation &key reconcile)`

Return a local WORKSPACE-PLAN for WORKSPACE and captured OBSERVATION.
Workspace/1 accepts a SNAPSHOT or no observation for a creation preview; an
exact captured topology produces no steps. Workspace/2 requires an explicitly
acquired WORKSPACE-STATE for the same workspace ID. A snapshot or incomplete
inspection cannot establish ownership. Matching acquired state remains usable
after its client closes. No acquisition, refresh or mutation occurs.

Owned planning separates declaration changes and captured drift. By default,
either requires explicit :RECONCILE before a plan can be returned; unsupported
changes remain conflicts. PLAN-DATA exposes diagnostics on a plan or
WORKSPACE-CONFLICT. An empty owned step vector can still require metadata
publication: inspect :PUBLISH-P. Application always reacquires and replans.
Non-NIL RECONCILE is invalid for workspace/1.


See also: [apply-workspace](#apply-workspace-function), [fetch-workspace-state](#fetch-workspace-state-function), [plan-data](#plan-data-function), [plan-steps](#plan-steps-function), [workspace-conflict](#workspace-conflict-type), [workspace-state](#workspace-state-type).

[Source](../src/workspace-api.lisp)

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

<a id="result-causes-function"></a>

### result-causes

`(result-causes result)`

Return retained application conditions in a fresh simple vector. No I/O.
Conditions keep primary-first order and identity deduplication; successful
applications without failures return an empty vector.


See also: [libtmux:error-cause](api.md#error-cause-function), [result-data](#result-data-function), [workspace-apply-failed](#workspace-apply-failed-type).

[Source](../src/workspace-api.lisp)

<a id="result-created-p-function"></a>

### result-created-p

`(result-created-p result)`

Return true when APPLY-WORKSPACE created the declared session.


See also: [apply-workspace](#apply-workspace-function), [result-outcomes](#result-outcomes-function), [result-snapshot](#result-snapshot-function).

[Source](../src/workspace.lisp)

<a id="result-data-function"></a>

### result-data

`(result-data result)`

Return owned application data and presence as two values, without I/O.
Accepts WORKSPACE-RESULT or WORKSPACE-APPLY-FAILED. Returns fresh data and T for
owned evidence; legacy evidence returns NIL,NIL. Data distinguishes phase,
mappings, selected/candidate/observed metadata and publication status.


See also: [failed-step](#failed-step-function), [result-causes](#result-causes-function), [result-outcomes](#result-outcomes-function), [result-snapshot](#result-snapshot-function).

[Source](../src/workspace-api.lisp)

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

<a id="state-causes-function"></a>

### state-causes

`(state-causes state)`

Return retained acquisition conditions in a fresh simple vector. No I/O.
Successful state has an empty vector. Original condition objects are shared.


See also: [libtmux:error-cause](api.md#error-cause-function), [workspace-state-error](#workspace-state-error-type).

[Source](../src/workspace-api.lisp)

<a id="state-data-function"></a>

### state-data

`(state-data state)`

Return fresh finite metadata for WORKSPACE-STATE or WORKSPACE-STATE-ERROR.
No I/O. Partial metadata from an error does not prove readiness or vacancy.


See also: [state-causes](#state-causes-function), [state-outcomes](#state-outcomes-function), [state-snapshot](#state-snapshot-function).

[Source](../src/workspace-api.lisp)

<a id="state-outcomes-function"></a>

### state-outcomes

`(state-outcomes state)`

Return STATE's read COMMAND-OUTCOME objects in a fresh simple vector.
Includes retained unsuccessful reads. No I/O.


See also: [libtmux:outcome-status](api.md#outcome-status-function), [state-causes](#state-causes-function).

[Source](../src/workspace-api.lisp)

<a id="state-snapshot-function"></a>

### state-snapshot

`(state-snapshot state)`

Return STATE's retained captured SNAPSHOT, or NIL before capture. No I/O.


See also: [fetch-workspace-state](#fetch-workspace-state-function), [libtmux:panes](api.md#panes-function), [state-data](#state-data-function).

[Source](../src/workspace-api.lisp)

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

<a id="workspace-inspection-type"></a>

### workspace-inspection

Explicit read evidence, including incomplete or invalid owned work.
An inspection cannot stand in for WORKSPACE-STATE in local planning.


See also: [inspect-workspace](#inspect-workspace-function), [inspection-data](#inspection-data-function), [workspace-inspection-error](#workspace-inspection-error-type).

[Source](../src/workspace-api.lisp)

Direct supertypes: `standard-object`.

<a id="workspace-inspection-error-type"></a>

### workspace-inspection-error

Inspection stopped with its original and terminal failures retained.
INSPECTION-EVIDENCE returns the partial public observation. Its causes remain
separate from INSPECTION-TERMINAL; neither admits planning or mutation.


See also: [inspection-causes](#inspection-causes-function), [inspection-evidence](#inspection-evidence-function), [inspection-terminal](#inspection-terminal-function).

[Source](../src/workspace-api.lisp)

Direct supertypes: `workspace-error`.

<a id="workspace-limit-exceeded-type"></a>

### workspace-limit-exceeded

A workspace JSON or file input exceeds a configured bound.

[Source](../src/workspace.lisp)

Direct supertypes: `invalid-workspace-document`.

<a id="workspace-plan-type"></a>

### workspace-plan

A finite local preview, with separate owned publication metadata.

[Source](../src/workspace.lisp)

Direct supertypes: `standard-object`.

<a id="workspace-result-type"></a>

### workspace-result

Retained workspace application evidence and final captured topology.

[Source](../src/workspace.lisp)

Direct supertypes: `standard-object`.

<a id="workspace-state-type"></a>

### workspace-state

Captured ready/vacant owned workspace evidence for local planning.
Acquire through FETCH-WORKSPACE-STATE. Readers remain usable after client close.


See also: [plan-workspace](#plan-workspace-function), [state-data](#state-data-function), [state-snapshot](#state-snapshot-function), [workspace-inspection](#workspace-inspection-type).

[Source](../src/workspace-api.lisp)

Direct supertypes: `standard-object`.

<a id="workspace-state-error-type"></a>

### workspace-state-error

Owned state acquisition failed with retained partial read evidence.
Failure does not imply vacancy or grant ownership. Inspect STATE-DATA,
STATE-SNAPSHOT, STATE-OUTCOMES and STATE-CAUSES without further I/O.


See also: [libtmux:error-cause](api.md#error-cause-function), [fetch-workspace-state](#fetch-workspace-state-function), [inspect-workspace](#inspect-workspace-function).

[Source](../src/workspace-api.lisp)

Direct supertypes: `workspace-error`.

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
VALIDATE is local. PLAN without an endpoint is local and requires workspace/1;
endpoint PLAN reads a snapshot or owned state before producing a local preview.
APPLY and owned-only INSPECT require --socket-path. --program selects the native
executable. The standalone --reconcile flag is owned-only for PLAN and APPLY.
Options and schema misuse fail before opening a client. The scoped client closes
without terminating the server. STDOUT receives one JSON result or help.
STDERR receives usage text or one JSON error retaining condition causes, failed
step data, and command outcomes, including byte arrays and unknown dispatch
status. An unavailable exit code or failed step is omitted. MAIN does not call
UIOP:QUIT, close caller streams, or enter the debugger.
Owned summaries add DATA with native lowercase keyword names. Vectors are arrays,
Boolean fields preserve false and absent optional values become null. Environment
and session-group associations are objects. Native snapshots are not serialized.
Completed INSPECT returns 0 even for busy or invalid ownership; DATA's COMPLETE-P
describes read completion, not readiness. Failed inspection retains its partial
data and original/terminal causes. Nested condition details stop after eight
levels and mark detailsTruncated. No command is automatically retried.


See also: [apply-workspace](#apply-workspace-function), [libtmux:outcome-phase](api.md#outcome-phase-function), [libtmux:outcome-status](api.md#outcome-status-function).

[Source](../src/workspace-cli.lisp)
