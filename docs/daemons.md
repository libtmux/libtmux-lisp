# Own an isolated tmux daemon

- Own a new daemon and its private endpoint with
  [libtmux:with-daemon](api.md#with-daemon-function).
- Connect to an existing server with
  [libtmux:with-client](api.md#with-client-function) alone.
- Closing a client leaves either kind of daemon running.

This function:

- starts an empty-configuration daemon and creates a session
- returns owned pane data
- on leaving the scope, stops and reaps the daemon and removes its socket and
  temporary directory

Full program (ASDF loading, entry point):
[managed-daemon.lisp](../examples/managed-daemon.lisp).

<!-- example:managed -->
```lisp
(defun inspect-owned-workspace (&key (program "tmux"))
  "Start an isolated daemon; return owned pane data after closing both resources."
  (libtmux:with-daemon (daemon :program program)
    (libtmux:with-client (client :program (libtmux:daemon-program daemon)
                                 :socket-path (libtmux:daemon-socket-path daemon))
      (let ((outcome (libtmux:new-session client :name "demo" :command '("/bin/cat"))))
        (when (libtmux:outcome-observation-error outcome)
          (error (libtmux:outcome-observation-error outcome))))
      (map 'list #'libtmux:entity-data
           (libtmux:panes (libtmux:fetch-snapshot client))))))
```
<!-- /example -->

From a source checkout ([setup](../.github/CONTRIBUTING.md#setup)):

```console
$ mise exec -- tools/lisp.sh examples/managed-daemon.lisp
```

Success prints `MANAGED DAEMON PASS` and one pane record. Set
`LIBTMUX_PROGRAM` to choose the tmux binary.

## Startup and lifetime

[libtmux:start-daemon](api.md#start-daemon-function):

- creates a fresh private socket directory
- starts a supervised foreground `tmux -D` child with `-f /dev/null`
- never adopts an existing server or loads configuration
- returns only after readiness IPC identifies the owned process and socket; a
  pathname or successful exec is not enough

Environment and directory:

- `:environment` is copied before launch. Omitted: inherit the caller's.
  `nil`: empty.
- Tmux selectors, socket activation and launcher controls are removed.
- The caller's locale is kept; the command transport's locale is not imposed.
- Values and executables are trusted application configuration. Bash may
  normalize its shell metadata.
- `:working-directory` affects only the child. Neither option changes the Lisp
  process.

The temporary parent defaults to UIOP's temporary directory.

- Canonical ancestors must belong to this user or root.
- Group- or world-writable ancestors need the sticky bit.
- Unix socket path-length limits apply.

Deadlines and limits:

- `:timeout` is one startup deadline for version identification, startup and
  readiness. It starts after input preparation.
- Half of `:output-limit` bounds lifetime diagnostics; the rest bounds version
  and readiness output. Minimum: two bytes.
- Cancelling the token after the readiness handoff does not stop the daemon.
- There is no lifetime timeout.

A background supervisor services the daemon's pipes and watches its process.

- There is no public async, control-mode or event API.
- [libtmux:daemon-state](api.md#daemon-state-function) returns local state.
  `:ready` means startup completed, not that the daemon is still alive.
- [libtmux:daemon-failure](api.md#daemon-failure-function) retains an
  unexpected exit.

## Shutdown and failure recovery

[libtmux:stop-daemon](api.md#stop-daemon-function) stops the child through its
retained handle, joins the worker and reaps the child.

- Checks the captured socket and directory identities before removing them.
- Refuses a substituted socket; never deletes unknown files recursively.
- Is idempotent: a second call also succeeds.
- Does not prove every pane descendant exited.

Stop waits are bounded:

- admission: at most 0.75 seconds
- worker join: at most 0.75 seconds
- retried job cleanup: at most 0.5 seconds

The budgets add up; OS work and scheduling can add more.

Failed cleanup signals
[libtmux:daemon-cleanup-failed](api.md#daemon-cleanup-failed-type) and keeps
the owner for an explicit retry. Nothing repeats automatically.

Startup failure attempts cleanup, then signals
[libtmux:daemon-start-failed](api.md#daemon-start-failed-type):

- [libtmux:error-cause](api.md#error-cause-function) returns the cause.
- [libtmux:error-daemon](api.md#error-daemon-function) returns the owner.
- [libtmux:pending-daemon-cleanups](api.md#pending-daemon-cleanups-function)
  lists owners with incomplete cleanup, including one whose constructor exited
  nonlocally without returning an owner.

To recover, inspect
[libtmux:daemon-cleanup-failures](api.md#daemon-cleanup-failures-function),
then call `stop-daemon` again on the same owner.

`with-daemon`:

- closes its original owner even if the variable is reassigned
- preserves body declarations, multiple values and the primary nonlocal exit
- propagates a cleanup failure after normal completion
- retains a cleanup failure during an existing exit instead of replacing that
  exit
