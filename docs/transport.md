# Clients and subprocess commands

`open-client` checks the selected tmux executable and returns a connection
scope. It does not start a daemon.

- Choose one of `:socket-name` or `:socket-path`. Omit both for tmux's default
  endpoint.
- `:config-file` is passed explicitly when given.
- Configuration strings are copied.

`with-client` closes the original client on every exit.

- The body supports declarations and preserves multiple values.
- Rebinding its visible variable does not change which resource closes.
- Closing releases the client's processes and streams. The tmux daemon keeps
  running.

## Command results

`run-command` takes a client and a finite list or vector of argv strings.

- Supply `:effect :read` or `:effect :mutation` explicitly.
- Arguments bypass shell parsing. tmux's command and format grammar still
  applies.
- It does not validate captured target identities. Named operations do; see
  the [operation contracts](operations.md).
- Optional `:input` is an octet vector, copied before dispatch.
- Standard output and diagnostic output are kept as bytes, including invalid
  UTF-8. `outcome-stdout`, `outcome-stderr` and `outcome-arguments` return
  owned copies.

An external command failure signals a condition:

- `error-outcome` retains the result.
- `error-cause` retains an underlying failure when present.
- `error-client` identifies the client, including a partially opened one that
  still owns cleanup work. Retry `close-client` on it if cleanup failed.

| Outcome status | Meaning |
| --- | --- |
| `:succeeded` | The child exited successfully and transport cleanup completed |
| `:failed` | The child reported a nonzero exit status |
| `:unknown` | Dispatch was possible but interruption, limits or cleanup prevented a complete result |
| `:not-dispatched` | Dispatch was prevented or the launcher positively reported an exec failure |

- Raw `outcome-phase` is `:prepared`, `:launching`, `:dispatched` or
  `:exited`. Named operations add `:preflight` and `:guard-rejected`; their
  [receipt and outcome policy](operations.md#outcomes-and-target-checks) is
  stricter than the raw runner's.
- Also inspect `outcome-reason`, `outcome-exit-code` and retained diagnostics.
- A command reporting failure can already have changed tmux. Statuses promise
  no rollback.
- The library never retries an uncertain mutation.

## Bounds and concurrency

Limits:

- Default command timeout: 30 seconds. Default combined stdout/stderr limit:
  16 MiB. Override per client or per command with `:timeout` and
  `:output-limit`.
- The deadline starts after validation, argument/environment copies,
  child-directory validation and executable inspection. It covers setup,
  launch and pipe service.
- It is an execution deadline, not a hard limit on caller wall time:
  synchronous setup and launch cannot be interrupted by its later checks.
- A byte limit retains at most the configured count.
- Input is written while both output pipes drain, so pipes cannot deadlock.

Concurrency:

- One external operation owns a client at a time. Concurrent work signals
  `client-busy` before dispatch. Use separate clients for independent
  operations.
- `make-cancellation-token` creates reusable one-way cancellation state. Pass
  it as `:cancel-token`, then call `cancel` from another thread.
- `cancel` returns true only for the first request. An idle token owns no OS
  descriptors.
- Cancellation signals `command-cancelled` and retains its dispatch evidence.
  It does not undo a completed mutation.

Closing rejects new operations, requests cancellation and waits for the owner.

- Normal process stop allows 50 ms before KILL and 500 ms for stop/drain.
  Final cleanup can wait another 500 ms for child exit.
- Client close allows 750 ms to join the active owner, after its initial
  lock/cancellation work. Lock acquisition and retained-job cleanup add time.
  Timed condition-wait reacquisition has no separate lock timeout.
- A failed join signals `cleanup-failed` and leaves the client closing.
- If child authority or cleanup cannot complete, the client retains the
  resources. Fix the underlying problem and retry `close-client`.
- `client-cleanup-failures` returns a fresh vector of retained secondary
  conditions.
- Cleanup failure after a normal scope return signals. During an existing error
  or nonlocal exit it is recorded without replacing that exit.
- Captured data stays usable locally after the client closes.

## Supported process boundary

The backend needs SBCL, x86-64 Linux and Bash.

- Linux must provide pidfds, eventfd and pidfd process-group signalling (Linux
  6.9 or newer), plus their libc wrappers.
- [`open-client`](api.md#open-client) checks the runtime profile before
  resolving the executable. The first open also probes pidfd/group
  signalling, eventfd and the launcher, then closes the temporary descriptors.
- [`unsupported-platform`](api.md#unsupported-platform) names the missing
  requirement through [`error-feature`](api.md#error-feature): `:runtime-profile`,
  `:pidfd`, `:pidfd-process-group`, `:eventfd` or `:launcher`.
  [`error-cause`](api.md#error-cause) retains a failed probe when available.
- The check is cached in the running image. It is not a continuing health
  monitor.
- Non-SBCL hosts have no replacement backend.

Launch:

- SBCL creates the child group for redirected stdin.
- A private FIFO exec barrier delays target execution until Lisp retains the
  pidfd, verifies the group and admits dispatch.
- argv passes as separate positional arguments. Caller strings are never
  evaluated as shell source.
- Only trusted native ELF executables are accepted. A script or tool-manager
  shim error names the selected file. Pass the underlying tmux binary through
  `open-client`'s `:program` argument.

Environment:

- Ordinary commands force `LC_ALL=C.UTF-8`, clear `TMUX` and `TMUX_PANE`, and
  normalize the Bash startup variables its fixed launcher uses. This is not a
  byte-for-byte environment transfer.
- Each private process job owns its environment and any explicit child working
  directory. Preparing or launching it leaves the Lisp process's environment
  and working directory alone.
- A separate daemon owner can use that boundary without imposing the command
  locale on new panes. [Managed daemon scopes](daemons.md) keep that
  environment and lifecycle separate.
- To change a running server's values, use explicit tmux environment
  operations.

Limits:

- The private descriptor poll does not run application REPL handlers.
- The library installs no process-wide subreaper.
- The bounds cover the supervised process group. They cannot force an
  uninterruptible kernel syscall to return, or contain a descendant that
  deliberately leaves the group.
- An unfinished launch remains owned and is reported as incomplete cleanup.

See the [architecture decision](adr/0001-native-common-lisp-engine.md#supervise-subprocesses-with-explicit-scopes-and-bounded-outcomes)
for launcher alternatives and saved-image limitations.

<a id="private-control-implementation"></a>

## Persistent control implementation

The optional `libtmux/control` system exposes scoped native connections,
queued requests and byte events through [`libtmux.control`](control-api.md).
See the [control guide](control.md) and its executable example.

- The engine reuses the process supervisor, one reader and serialized request
  writes.
- Requests queue without waiting. Awaiting a result and receiving an event
  have separate timeout results.
- Closing cancels pending work, joins the owned worker and leaves the daemon
  running.
- The live daemon must be tmux 3.8 or newer, so native notifications are
  deferred until a command reply ends. The 3.7 series can put pause/continue
  notices inside replies. The version comes from the daemon witness. Core
  operations still support tmux 3.3a and newer.

Limits:

- Reply bytes, pending requests and event delivery have separate finite limits.
- An expired queued request is never dispatched.
- An in-flight deadline closes the connection and retains partial replies and
  dispatch state.
- Awaiting with a shorter timeout leaves the request live.
- Event overflow drops the oldest events and reports a gap with event and byte
  counts.
- Completion means the native command queue progressed. Application readiness
  needs its own signal.

Line assembler (LF):

- Accepts split octet chunks, keeps every byte except the terminating LF, and
  returns owned line vectors.
- Separate limits bound each line, each feed's bytes and each returned batch's
  line count.
- A truncated EOF signals a decoding error.
- A resource failure, cancellation or escaping exit retires the decoder. It
  cannot resume after losing consumed input.

Pane-output decoder:

- Keeps NUL, invalid UTF-8 and all other bytes.
- Understands tmux's three-digit octal escapes and extended-output age and
  reserved fields.
- Encoded and decoded byte limits are separate.
- Codecs own no queues or workers. The persistent owner supplies them.

The engine follows tmux's ordinary reply guards and notification conventions.

- It sends a separate completion command after each request, so a failed
  command does not strand the next one.
- It never retries a mutation or reconnects on its own.
- See the
  [architecture record](adr/0001-native-common-lisp-engine.md#qualify-control-mode-and-source-filtering-before-exposing-them)
  for the remaining reconnect, event coverage and compatibility work.
