# Own an isolated tmux daemon

Use [libtmux:with-daemon](api.md#with-daemon-function) when your application owns
both a new tmux daemon and its private endpoint. Use
[libtmux:with-client](api.md#with-client-function) alone when connecting to an
existing server. Closing a client leaves either kind of daemon running.

This function starts with empty configuration, creates one session, acquires
its panes and returns ordinary owned data. Leaving the outer scope stops and
reaps the daemon and removes its checked socket and temporary directory.
The [complete program](../examples/managed-daemon.lisp) includes ASDF loading,
assertions and an entry point.

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

From the source checkout with the pinned toolchain installed:

```console
$ mise exec -- tools/lisp.sh examples/managed-daemon.lisp
```

Success prints `MANAGED DAEMON PASS` and one pane record. The same program runs
from the extracted source archive in `mise run package-examples`. To select a
particular native binary, set `LIBTMUX_PROGRAM` for this example.

## Startup and lifetime

[libtmux:start-daemon](api.md#start-daemon-function) creates a fresh private
socket directory and starts a supervised foreground `tmux -D` child with
`-f /dev/null`. It does not adopt an existing server or load arbitrary
configuration. It returns after completed readiness IPC identifies the owned
process and socket; a pathname or successful exec alone is insufficient.

The selected environment is copied before launch. Omission inherits the
caller's environment; `:environment nil` selects an empty input environment.
Tmux selectors, socket activation and launcher controls are removed. The caller
locale is preserved instead of imposing the ordinary command transport's
locale on the new server. Environment values and executables remain trusted
application configuration; Bash may normalize its shell metadata.
`:working-directory` affects only the child. Neither option changes the Lisp
process environment or directory.

The temporary parent defaults to UIOP's temporary directory. Its canonical
ancestors must belong to this user or root; group/world-writable ancestors must
have the sticky bit. Unix socket path-length limits also apply.

`:timeout` is a single startup deadline covering version identification,
startup and readiness, beginning after input preparation. Half of
`:output-limit` bounds daemon lifetime diagnostics; the remainder bounds
version/readiness output. The minimum is two bytes. Startup cancellation ends
at the atomic readiness handoff: cancelling the supplied token afterward does
not stop the daemon. No lifetime timeout is implied.

A background supervisor services the daemon's pipes and watches its process.
This resource does not provide a public async, control-mode or event API.
[libtmux:daemon-state](api.md#daemon-state-function) returns local state;
`:ready` records completed startup, not future liveness. Unexpected exit is
retained through [libtmux:daemon-failure](api.md#daemon-failure-function).

## Shutdown and failure recovery

[libtmux:stop-daemon](api.md#stop-daemon-function) uses retained child authority,
joins the worker and reaps the child. It checks the captured socket and directory
identities before removing them. It refuses a substituted socket and never
recursively deletes unknown files. Success is idempotent. Stopping the daemon
does not prove that every pane descendant exited.

A stop has separate admission and worker-join waits of at most 0.75 seconds
apiece, followed by any retried job cleanup (up to 0.5 seconds). These are
additive cleanup budgets; synchronous OS work and scheduling can extend caller
wall time. Failed cleanup signals
[libtmux:daemon-cleanup-failed](api.md#daemon-cleanup-failed-type) and retains the
owner for an explicit retry. No mutation is automatically repeated.

Startup failure attempts cleanup before signalling
[libtmux:daemon-start-failed](api.md#daemon-start-failed-type).
[libtmux:error-cause](api.md#error-cause-function) retains the cause and
[libtmux:error-daemon](api.md#error-daemon-function) retains the owner.
[libtmux:pending-daemon-cleanups](api.md#pending-daemon-cleanups-function) also
returns owners with incomplete cleanup, including a constructor that left
through a nonlocal exit without returning an owner. Inspect
[libtmux:daemon-cleanup-failures](api.md#daemon-cleanup-failures-function), then
retry `stop-daemon` on that same owner.

`with-daemon` closes its original owner even if the visible variable is
reassigned. It preserves body declarations, multiple values and primary
nonlocal exits. A cleanup failure after normal completion propagates; during
an existing exit it is retained without replacing that exit.
