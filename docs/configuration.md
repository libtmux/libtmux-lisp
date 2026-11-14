# Decoded configuration

- [`show-option`](api.md#show-option-function) returns one typed value and its
  presence.
- [`show-options`](api.md#show-options-function) returns owned records naming
  the selected table and inheritance source.
- Both read tmux now; neither refreshes a retained snapshot.
- Options, hooks and environment need an explicit scope. Local scopes also need
  a captured target from the same client.

## Runnable inspection

The [program](../examples/configuration.lisp) needs only the core ASDF system.
It:

- starts an isolated daemon and creates a session
- reads false and inherited options, a hook and a hidden environment entry
- closes both resources before returning plain data

Run it from a source checkout ([setup](../.github/CONTRIBUTING.md#setup)):

```console
$ mise exec -- tools/lisp.sh examples/configuration.lisp
```

It prints `CONFIGURATION PASS`. The core function:

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
presence and a fresh vector of native read outcomes.

- Present false: `(values nil t outcomes)`. Absent: `(values nil nil outcomes)`.
- An empty string or array is present.
- Use `multiple-value-bind` when presence matters.

The collection readers return two values: a fresh vector of owned plists and a
fresh vector of native outcomes.

- Option records hold name, requested scope and target ID, catalog version,
  type, array status, presence, value, source scope and target ID, and
  inherited status.
- Records hold no client or captured handle. Editing them changes local data
  only.

`include-inherited` defaults to true. Lookup falls back:

- session to global session
- window to global window
- pane to window, then global window

Inheritance checks:

- Every absent table that could shadow the chosen ancestor is checked again.
- A newly present shadow retries the name, at most three times, under the same
  limits.
- Pane inheritance also checks its captured window relationship.
- The result still spans an acquisition interval and is not a transaction.
- Read hooks can run more than once.

Arrays:

- The whole array is read before an optional getter `key` selects an entry.
- Sparse keys stay `(key-text . typed-value)` pairs in a vector. Supported
  string keys stay strings.
- A missing key in a present local array does not fall through to the parent.
- Keys are validated against the live catalog before payload reads.
- Key text is copied before I/O and limited to 1 MiB of UTF-8.

`names`:

- Omitted: all registered built-in non-hook options, in source order.
  [`show-hooks`](api.md#show-hooks-function) lists built-in hooks instead.
- An explicit list or vector keeps requested order and duplicates, including
  supported user names.
- At most 4096 names, each at most 1 MiB of UTF-8. Raising `record-limit` does
  not raise these caps.
- Explicit `nil` or `#()` returns fresh empty vectors with no I/O.

Hook values are inert canonical tmux source, never Lisp forms. Inspection
never runs a hook through `set-hook -R`.

## Environment state

[`show-environment`](api.md#show-environment-function) needs explicit finite
`names` and a `:global` or `:session` scope.

- It reads the raw table, not the environment a new child would inherit.
- `:state` is `:present`, `:removed` or `:absent`. Empty text is `:present`.
- Present and removed records carry `:hidden-p`. Absent records make no
  visibility claim.

Reading:

- Ordinary visibility is checked first, then hidden visibility after an empty
  success.
- Contradictory views retry under the original limits.
- Names may contain Unicode or newlines; they must be nonempty UTF-8 without
  NUL or `=`. This is broader than the names mutations accept.

## Limits and failure evidence

- One client lease, cancellation token, deadline and output budget cover
  preflight and every read and recheck.
- `record-limit` defaults to 4096. It charges decoded rows and negative
  observations, retries included.
- `value-limit` defaults to 1 MiB per decoded UTF-8 value.
- Client timeout and output defaults apply.
- Preparation, platform calls and cleanup add wall time. See
  [transport deadlines](transport.md#bounds-and-concurrency).

[`configuration-read-failed`](api.md#configuration-read-failed-type) keeps the
original cause, active name and scope, native evidence, all read outcomes and
earlier fully resolved records.

- `error-cause` identifies the failure.
- `error-outcome` is the cause's outcome or the current leaf outcome. It can be
  `nil` before that read.
- Accessors return owned data or fresh outcome containers.
- A native missing-name failure stays a failed outcome even when its
  diagnostics establish absence.
- A valid positive observation before a later hook failure can remain in
  [`outcome-value`](api.md#outcome-value-function). The acquisition still
  failed.
- Cancellation, truncated output and exhausted limits never become absence or
  complete arrays.

Trust and scope:

- The reader parses ordinary subprocess output in the native printer schema and
  trusts it. It does not authenticate each leaf against hook-generated records.
- Extra unrelated output fails decoding. Use the
  [raw text inspectors](operations.md#configuration-inspection) for
  unrestricted native output.
- The one-shot control route is withdrawn and disabled. Decoded reads do not
  need it at either end of the supported tmux range.
