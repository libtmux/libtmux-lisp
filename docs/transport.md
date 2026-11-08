# Clients and subprocess commands

`open-client` checks the selected tmux executable and returns a connection
scope. It does not start a daemon. Choose one of `:socket-name` or
`:socket-path`; omitting both selects tmux's default endpoint. `:config-file`
is passed explicitly when provided. Configuration strings are copied.

`with-client` closes the original client on every exit. The body supports
declarations and preserves multiple values. Rebinding its visible variable
does not change the resource to close. Closing releases the client's processes
and streams; it leaves the tmux daemon running.

## Command results

`run-command` takes a client and a finite list or vector of argv strings.
Supply `:effect :read` or `:effect :mutation` explicitly. Arguments bypass
shell parsing, but tmux's command and format grammar still applies. This
escape hatch does not validate captured target identities. Named entity
operations provide that validation; see the [operation contracts](operations.md).

The optional `:input` is an octet vector, copied before dispatch. Standard
output and diagnostic output are retained as bytes, including invalid UTF-8.
`outcome-stdout`, `outcome-stderr` and `outcome-arguments` return owned copies.
An external command failure signals a condition whose `error-outcome` retains
the result and whose `error-cause` retains an underlying failure when present.
`error-client` identifies the client, including a partially opened client that
still owns cleanup work. Retry `close-client` on that object if cleanup failed.

| Outcome status | Meaning |
| --- | --- |
| `:succeeded` | The child exited successfully and transport cleanup completed |
| `:failed` | The child reported a nonzero exit status |
| `:unknown` | Dispatch was possible but interruption, limits or cleanup prevented a complete result |
| `:not-dispatched` | Dispatch was prevented or the launcher positively reported an exec failure |

Raw `outcome-phase` records `:prepared`, `:launching`, `:dispatched` or
`:exited`; named operations also use `:preflight` and `:guard-rejected`.
Their [receipt and outcome policy](operations.md#outcomes-and-target-checks)
requires more evidence than the raw process runner. Inspect `outcome-reason`,
`outcome-exit-code` and retained diagnostics
as well. A command reporting failure can already have changed tmux; these
statuses do not promise rollback. The library never retries an uncertain
mutation automatically.

## Bounds and concurrency

The default command timeout is 30 seconds. The default combined stdout/stderr
limit is 16 MiB. Override these through client defaults or per-command
`:timeout` and `:output-limit`. The low-level deadline starts after validation,
argument/environment copies, selected child-directory validation and executable
inspection. It charges setup, launch and pipe
service, but synchronous setup/launch cannot be interrupted by its later checks.
The gate rechecks admission before releasing the target. This is an execution
deadline, not a hard limit on caller wall time. A byte limit retains at most the
configured count.
Input is written while both output pipes are drained, avoiding pipe deadlock.

One external operation owns a client at a time; concurrent work signals
`client-busy` before dispatch. Use separate clients for independent operations.
`make-cancellation-token` creates reusable one-way cancellation state; pass it
as `:cancel-token`, then call `cancel` from another thread. `cancel` returns
true only for the first request. An idle token owns no OS descriptors.
Cancellation signals `command-cancelled` from the operation and retains its
dispatch evidence; it does not undo a completed mutation.

Closing rejects new operations, requests cancellation and waits for the owner.
Normal process stop allows 50 ms before KILL and 500 ms for stop/drain. Final
cleanup can separately wait another 500 ms for child exit. Client close has a
750 ms active-owner join allowance after its initial lock/cancellation work;
lock acquisition and retained-job cleanup add time. Timed condition-wait
reacquisition has no separate lock timeout. A failed join signals
`cleanup-failed` and leaves the client closing. If child authority or cleanup
cannot be completed, the client retains the resources. Correct the underlying
resource problem and retry `close-client`. `client-cleanup-failures` returns a
fresh vector of retained secondary conditions.

Cleanup failure after a normal scope return signals. During an existing error
or nonlocal exit it is recorded without replacing that exit. Captured data
remains usable locally after client closure.

## Supported process boundary

The first backend targets SBCL on Linux x86-64. It requires pidfds, eventfd,
pidfd process-group signalling (Linux 6.9 or newer), their libc wrappers, and
Bash. [`open-client`](api.md#open-client) checks the runtime profile before
resolving the executable. The first open also probes pidfd/group signalling,
eventfd and the launcher, closing the temporary descriptors before proceeding.
[`unsupported-platform`](api.md#unsupported-platform) identifies the requirement
through [`error-feature`](api.md#error-feature): `:runtime-profile`, `:pidfd`,
`:pidfd-process-group`, `:eventfd` or `:launcher`.
[`error-cause`](api.md#error-cause) retains a failed probe when available.
The check is cached in the running image; it is not a continuing health monitor
or qualification of another implementation or platform. Non-SBCL hosts have no
replacement backend. SBCL creates the child
group for redirected stdin. A private FIFO exec barrier delays target execution
until Lisp retains the pidfd, verifies the group and admits dispatch. It passes
argv as separate positional arguments and does not evaluate caller strings as
shell source.
Only trusted native ELF target executables are accepted. A script or
tool-manager shim error names the selected file; pass the underlying tmux
binary through `open-client`'s `:program` argument.

Ordinary commands force `LC_ALL=C.UTF-8`, clear `TMUX` and `TMUX_PANE`, and normalize
Bash startup variables used by its fixed launcher. It is not a byte-for-byte
environment transfer API. Each private process job owns its selected environment
and any explicit child working directory; preparing or launching it does not change the Lisp
process's environment or working directory. A separate daemon owner can use
that boundary without imposing the command locale on newly created panes;
[managed startup remains unqualified](adr/0001-native-common-lisp-engine.md#keep-daemon-bootstrap-separate-from-client-connection).
Use explicit tmux environment operations to change a running server's values.
The private descriptor poll does not run application REPL
handlers. The library does not install a process-wide subreaper.

The bounds cover the supervised process group. They cannot force an
uninterruptible kernel syscall to return or contain a descendant that
deliberately leaves that group. An unfinished launch remains owned and is
reported as incomplete cleanup.

See the [architecture decision](adr/0001-native-common-lisp-engine.md#supervise-subprocesses-with-explicit-scopes-and-bounded-outcomes)
for launcher alternatives and saved-image limitations.
