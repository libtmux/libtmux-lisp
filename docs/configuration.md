# Decoded configuration

Use [`show-option`](api.md#show-option-function) for a typed value and presence,
or [`show-options`](api.md#show-options-function) for owned records describing
the selected table and inheritance source. These functions acquire state now;
they do not refresh a retained snapshot. Options, hooks and environment tables
require an explicit scope. Local scopes also require a captured target from
the supplied client.

## Runnable inspection

This complete [program](../examples/configuration.lisp) starts an isolated daemon,
creates a session, reads false and inherited options, inspects a hook and reads
a hidden environment entry. Both resource scopes close before the returned
ordinary data is inspected. It requires only the core ASDF system.

Run from a source checkout with the [pinned tools](../.github/CONTRIBUTING.md#setup):

```console
$ mise exec -- tools/lisp.sh examples/configuration.lisp
```

The program prints `CONFIGURATION PASS` after checking the values and cleanup.
The following function is extracted from that tested program:

<!-- example:decodedconfiguration -->
```lisp
(defun inspect-configuration (&key (program "tmux"))
  "Return owned option, hook and environment records from an isolated daemon."
  (libtmux:with-daemon (daemon :program program)
    (libtmux:with-client (client :program (libtmux:daemon-program daemon)
                                 :socket-path (libtmux:daemon-socket-path daemon))
      (libtmux:new-session client :name "configuration" :command '("/bin/cat"))
      (let ((session (aref (libtmux:fetch-sessions client) 0)))
        (libtmux:set-option client "renumber-windows" nil :scope :session :target session)
        (libtmux:set-option client "@project" "editor" :scope :global-session)
        (libtmux:set-hook client "after-new-window" "display-message ready" :scope :session :target session)
        (libtmux:set-environment client "PROJECT_TOKEN" "local-only" :scope :session :target session :hidden t)
        (list :options (libtmux:show-options client :scope :session :target session
                                                   :names '("renumber-windows" "@project" "@absent"))
              :hooks (libtmux:show-hooks client :scope :session :target session
                                               :names '("after-new-window"))
              :environment (libtmux:show-environment client :scope :session :target session
                                                           :names '("PROJECT_TOKEN")))))))
```
<!-- /example -->

## Values and inherited tables

[`show-option`](api.md#show-option-function) returns three values: value,
presence and a fresh vector of native read outcomes. Present false is
`(values nil t outcomes)`; absence is `(values nil nil outcomes)`. An empty
string or array is present. Use `multiple-value-bind` when presence matters.

The collection readers return two values: a fresh simple vector of owned
plists, and a fresh vector of native outcomes. Option records include name,
requested scope/target ID, exact catalog version, type, array status, presence,
value, source scope/target ID and inherited status. Records contain no client
or captured handle. Editing their strings or containers changes local data only.

`include-inherited` defaults to true. Session lookup falls back to global session;
window lookup to global window; pane lookup to window, then global window.
Every absent table that could shadow the chosen ancestor is checked again.
A newly present shadow retries the name, at most three times, under the same
limits. Pane inheritance also checks its captured window relationship. This
reduces detectable contradictions; the result still spans an acquisition
interval and is not a transaction. Read hooks can run more than once.

An array is acquired whole before an optional getter `key` selects an entry.
Sparse keys remain `(key-text . typed-value)` pairs in a vector; supported string
keys stay strings. A missing key in a present local array does not fall through
to the parent. Key validation uses the exact live catalog before payload reads.
Mutable key text is copied before I/O and limited to 1 MiB UTF-8.

Omitted `names` enumerates registered built-in non-hook options in source order.
[`show-hooks`](api.md#show-hooks-function) enumerates built-in hooks instead.
Explicit lists/vectors preserve requested order and duplicates, including
supported user names. At most 4096 names are accepted, with a 1 MiB UTF-8 limit
per name; raising `record-limit` does not raise these input caps.
Explicit `nil` or `#()` returns fresh empty vectors with
no I/O. Hook values are inert canonical tmux source, never Lisp forms; inspection
does not request hook execution through `set-hook -R`.

## Environment state

[`show-environment`](api.md#show-environment-function) requires explicit finite
`names` and a `:global` or `:session` scope. It reads that raw table, without
constructing the environment a new child process would inherit. Present entries,
removal markers and absence have distinct `:state` values: `:present`, `:removed`
and `:absent`. Empty text remains present. Present/removal records carry an
explicit `:hidden-p`; absent records make no visibility claim.

The reader checks ordinary visibility first, then hidden visibility after an
empty success. Contradictory views retry under the original limits. Native names
may contain Unicode or newlines; they must be nonempty UTF-8 without NUL or `=`.
This read grammar is broader than the identifier grammar used for mutations.

## Limits and failure evidence

One client lease, cancellation token, deadline and aggregate output budget covers
preflight and all selected reads/rechecks. The default `record-limit` is 4096;
it charges decoded rows and negative observations, including retries. The
default `value-limit` is 1 MiB per decoded UTF-8 value. Client timeout/output
defaults apply. Preparation, platform calls and cleanup add caller wall time;
see [transport deadlines](transport.md#bounds-and-concurrency).

[`configuration-read-failed`](api.md#configuration-read-failed-type) retains the
original cause, active name/scope, native evidence, all read outcomes and prior
fully resolved records. `error-outcome` is the cause-associated or current-leaf
outcome, possibly `nil` before that read; `error-cause` identifies the failure.
Its accessors return owned data or fresh outcome
containers. Native missing-name failures remain failed outcomes even when their
exact diagnostics establish absence. A valid positive observation before a later
hook failure can remain in [`outcome-value`](api.md#outcome-value-function);
it does not turn the failed acquisition into success. Cancellation, truncated
output and exhausted limits never become absence or complete arrays.

The reader uses ordinary subprocess output and the exact reviewed native printer
schema. It assumes trusted command output; it does not authenticate each leaf
against hook-generated records. Extra unrelated output fails decoding. Use the
[raw text inspectors](operations.md#configuration-inspection) when unrestricted
native output is the desired result. The withdrawn one-shot control route stays
disabled; decoded reads work at both supported tmux endpoints without it.
