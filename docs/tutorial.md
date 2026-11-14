# Capture, inspect and build a workspace

This tutorial builds two sessions, three physical windows, four links and four
panes on a private tmux daemon, then inspects them as ordinary Lisp data. It
touches no other tmux server.

Start with the [source installation](../README.md#install-from-source).

## Run the walkthrough

```console
$ mise run examples
```

The runner:

- creates a private temporary directory and socket, and clears inherited tmux
  variables
- starts an empty-configuration daemon and runs the shipped Lisp examples
- stops its own server
- exits nonzero on any failure

Use another tmux binary:

```console
$ LIBTMUX_TEST_TMUX=/usr/bin/tmux mise run examples
```

## Work at the REPL

Start the REPL from the checkout root. It starts, uses and stops its own
private daemon, so nothing else on the host is touched.

```console
$ mise run repl
```

Load the query system (it loads the core). The REPL loads no system on its own:

```lisp
(asdf:load-system "libtmux/query")
```

Load the optional systems used below:

```lisp
(asdf:load-system "libtmux/regex")
```

```lisp
(asdf:load-system "libtmux/json")
```

```lisp
(asdf:load-system "libtmux/workspace")
```

Load the recipes. Their package defines the SBCL package-local nicknames `tm`
(core), `q` (query), `j` (JSON) and `ws` (workspace). The library defines no
global nicknames.

```lisp
(load "examples/workspace.lisp")
```

```lisp
(in-package #:libtmux.examples)
```

Start a private daemon. The library owns it and removes its socket directory
when you stop it:

```lisp
(defparameter *daemon* (tm:start-daemon))
```

```lisp
(defparameter *socket-path* (tm:daemon-socket-path *daemon*))
```

Create session `work` with one `editor` window. The outcome status is
`:succeeded`:

```lisp
(tm:with-client (client :program (tm:daemon-program *daemon*)
                        :socket-path *socket-path*)
  (tm:outcome-status
   (tm:new-session client :name "work" :window-name "editor"
                          :width 120 :height 40 :command '("/bin/cat"))))
```

This captures the graph and returns one record: session `work`, its `editor`
window and one pane. Pane data holds identity, captured fields, provenance and
relationship IDs:

```lisp
(inspect-workspace *socket-path*)
```

## Build a linked workspace

The recipe comes from [workspace.lisp](../examples/workspace.lisp). It:

- creates a `logs` window and a `review` session
- splits `editor`
- links the `editor` window into `review` at index 7
- renames `logs` to `logs #{literal}`, keeping the format text literal

Run it once on the fresh demo. A second run fails on the existing names.

<!-- example:workspace -->
```lisp
(defun create-workspace (client)
  "Extend the demo's WORK session; return a fresh captured graph.
Creates a logs window, a second editor pane, a review session and a shared link.
The caller owns the isolated daemon; repeating this recipe there is an error."
  (let* ((before (tm:fetch-snapshot client))
         (work (find "work" (tm:sessions before) :key #'tm:name :test #'string=)))
    (unless work (error "Start the demo's WORK session first"))
    (let* ((editor-link (aref (tm:window-links work) 0))
           (editor (tm:window editor-link))
           (pane (aref (tm:panes editor) 0))
           (logs (observed-value
                  (tm:new-window client work :name "logs" :command '("/bin/cat"))))
           (review (observed-value
                    (tm:new-session client :name "review" :window-name "notes"
                                          :command '("/bin/cat")))))
      (tm:split-pane client pane :direction :horizontal :command '("/bin/cat"))
      (tm:link-window client editor-link review 7)
      (tm:rename-window client logs "logs #{literal}")
      (tm:fetch-snapshot client))))
```
<!-- /example -->

Keep the captured graph after the client closes. The global is REPL scratch,
not a library convention:

```lisp
(defparameter *snapshot*
  (tm:with-client (client :socket-path *socket-path*)
    (create-workspace client)))
```

```lisp
(list (length (tm:sessions *snapshot*))
      (length (tm:windows *snapshot*))
      (length (tm:window-links *snapshot*))
      (length (tm:panes *snapshot*)))
```

The result is `(2 3 4 4)`: sessions, windows, links, panes.

- The two `editor` links differ in session and index, and share one physical
  window.
- `windows` on a snapshot deduplicates physical windows.
- `windows` on a session keeps one entry per link.

All traversal directions: [captured objects](captures.md).

## Select and project locally

<!-- example:selection -->
```lisp
(defun wide-active-panes (snapshot)
  "Select captured active panes at least 40 cells wide; no tmux commands."
  (loop for pane across (tm:panes snapshot)
        when (and (tm:active-p pane) (>= (tm:width pane) 40))
          collect (tm:entity-data pane)))
```
<!-- /example -->

```lisp
(wide-active-panes *snapshot*)
```

This returns a nonempty list of plists from the retained graph. Plain sequence
functions (`map`, `find-if`, `count-if`, `reduce`, `remove-if`) work on it too.
None of these contact tmux.

Compile a reusable scalar filter to validate, inspect or share a selection.
`q` is the package-local nickname for `libtmux.query`.

<!-- example:query -->
```lisp
(defparameter *wide-active-filter*
  (q:compile-filter
   :pane
   '(:and (:= :pane/active t)
          (:>= :pane/width 40))))

(defun wide-active-pane-data (snapshot)
  "Return owned data for captured active panes at least 40 cells wide; no I/O."
  (map 'vector #'tm:entity-data
       (q:matching *wide-active-filter* (tm:panes snapshot))))
```
<!-- /example -->

```lisp
(wide-active-pane-data *snapshot*)
```

- `matching` returns a fresh simple vector in captured order.
- Compilation copies the query form and checks field types, cycles and
  resource limits.
- Neither compilation nor matching contacts tmux. A compiled filter is plain
  Lisp over retained observations.

Traverse relationships locally and keep the eager selection in a QuerySet that
records its root model:

<!-- example:relation -->
```lisp
(defparameter *active-session-filter*
  (q:compile-filter
   :session
   '(:any :session/window-links
     (:is :link/window
      (:any :window/panes
       (:= :pane/active t))))))

(defun active-session-data (snapshot)
  "Return owned data for sessions with an active pane; no I/O."
  (map 'vector #'tm:entity-data
       (q:items
        (q:where (q:from (tm:sessions snapshot) :model :session)
                 *active-session-filter*))))
```
<!-- /example -->

More: [native query guide](queries.md) (quantifier identities, stable
ordering, ownership, strict cardinality).

## Match and serialize an optional query

`libtmux/regex` adds CL-PPCRE operators. Core and `libtmux/query` do not depend
on CL-PPCRE. The scanner compiles once with the filter:

<!-- example:regex -->
```lisp
(defparameter *cat-command-filter*
  (q:compile-filter
   :pane
   '(:regex-full-match :pane/current-command
     (:cl-ppcre "CAT" :case-insensitive-mode t))))

(defun cat-pane-data (snapshot)
  "Return owned data for captured panes whose command is exactly cat; no I/O."
  (map 'vector #'tm:entity-data
       (q:matching *cat-command-filter* (tm:panes snapshot))))
```
<!-- /example -->

```lisp
(cat-pane-data *snapshot*)
```

`libtmux/json` writes the native schema `libtmux.lisp.filter/1`. Reading a regex
filter needs `:allow-regex t`, because parser limits do not interrupt a
CL-PPCRE scan:

<!-- example:filterdocument -->
```lisp
(defun round-trip-filter-document (snapshot)
  "Round-trip the checked regex filter and apply it to one retained snapshot."
  (let* ((document (j:write-filter *cat-command-filter*))
         (restored (j:read-filter document :allow-regex t)))
    (values document
            (map 'vector #'tm:entity-data
                 (q:matching restored (tm:panes snapshot))))))
```
<!-- /example -->

```lisp
(round-trip-filter-document *snapshot*)
```

Both are local. More: [interchange guide](query-interchange.md) (closed
envelope, limits, false/empty/null).

Use both values when false and absence differ. This field is always present,
so an inactive pane returns `nil` and `t`:

```lisp
(let ((pane (find-if-not #'tm:active-p (tm:panes *snapshot*))))
  (multiple-value-bind (value present-p) (tm:field-value pane :pane/active)
    (list value present-p)))
```

- Returned strings, plists and relation vectors are caller-owned copies.
- `entity-data` holds relationship IDs, not a recursive graph.
- Editing a copy never changes tmux.

More: [field reference](fields.md) (types, optional values).

## Handle command and observation outcomes

Creation and named mutations return a
[command-outcome](api.md#command-outcome-type).

- A command can succeed with no observation: its target may vanish afterward.
- Check the observation separately. This helper never retries the mutation:

<!-- example:outcome -->
```lisp
(defun observed-value (outcome)
  "Return an operation's observed value, or signal its observation failure."
  (when (tm:outcome-observation-error outcome)
    (error (tm:outcome-observation-error outcome)))
  (multiple-value-bind (value present-p) (tm:outcome-value outcome)
    (unless present-p
      (error "This operation did not return an observation"))
    value))
```
<!-- /example -->

Rename a captured window and compare the old and new observations:

```lisp
(tm:with-client (client :socket-path *socket-path*)
  (let* ((snapshot (tm:fetch-snapshot client))
         (window (find "editor" (tm:windows snapshot) :key #'tm:name :test #'string=))
         (renamed (observed-value (tm:rename-window client window "api #{literal}"))))
    (list (tm:name window) (tm:name renamed) (tm:same-entity-p window renamed))))
```

The result is `("editor" "api #{literal}" t)`.

- Format punctuation survives literally.
- Refresh uses the **same client context** and returns a new observation.
- Observations from a different connection are not interchangeable targets,
  even when their numeric IDs match.

External failures signal typed conditions. A handler can read:

- [error-outcome](api.md#error-outcome-function)
- [outcome-status](api.md#outcome-status-function)
- [outcome-phase](api.md#outcome-phase-function)
- [outcome-exit-code](api.md#outcome-exit-code-function)
- owned diagnostic bytes

Missing completion evidence can mean the mutation already happened. A blind
retry can duplicate effects. Details:
[operation guide](operations.md#outcomes-and-target-checks).

## Preserve binary data

<!-- example:buffers -->
```lisp
(defun round-trip-bytes (client)
  "Store and retrieve a named binary buffer, including NUL and invalid UTF-8."
  (let ((bytes (make-array 5 :element-type '(unsigned-byte 8)
                           :initial-contents '(0 10 92 195 255))))
    (tm:set-buffer client bytes :name "example bytes")
    (multiple-value-bind (actual outcome)
        (tm:show-buffer client :name "example bytes")
      (assert (eq :succeeded (tm:outcome-status outcome)))
      (assert (equalp bytes actual))
      actual)))
```
<!-- /example -->

```lisp
(tm:with-client (client :socket-path *socket-path*) (round-trip-bytes client))
```

- This returns the five octets unchanged, NUL and invalid UTF-8 included.
- `capture-pane` returns UTF-8 text and an outcome. `capture-pane-bytes`
  returns octets.
- Captures and buffer reads are bounded, complete results, not streams.

Input and pipes:

- A successful send does not prove the application is ready or consumed the
  input. Wait on an application signal, not a sleep or printed text.
- `pipe-pane` sets up a daemon-owned shell pipe. Ownership:
  [pane processes](operations.md#pane-processes).

## Drive an application without polling

The shipped [worker](../examples/worker.sh) signals readiness, reads one
request, writes a receipt file, then signals consumption.

- The Lisp controller waits on a fresh `wait-for` channel per signal.
- The receipt file proves what the application consumed. A successful send or
  printed marker does not.
- Calls block with deadlines. This is not a control-mode subscription API.

<!-- example:worker -->
```lisp
(defun drive-worker (client session socket-path program worker-path receipt-path)
  "Launch a worker through argv, wait for readiness and verify input consumption.
WORKER-PATH names the shipped worker.sh; RECEIPT-PATH is in the owned demo directory.
Signals operational conditions without retrying a mutation. Calls block."
  (let* ((ready (symbol-name (gensym "example-ready-")))
         (consumed (symbol-name (gensym "example-consumed-")))
         (window (observed-value
                  (tm:new-window client session :name "worker"
                                 :command (list "/bin/sh" worker-path program
                                                socket-path ready consumed receipt-path))))
         (pane (aref (tm:panes window) 0))
         (message "release #{literal}; λ"))
    (tm:run-command client (list "-N" "wait-for" ready)
                    :effect :read :timeout 1 :output-limit 4096)
    (tm:send-text client pane message :enter t)
    (tm:run-command client (list "-N" "wait-for" consumed)
                    :effect :read :timeout 1 :output-limit 4096)
    (let ((receipt (uiop:read-file-string receipt-path :external-format :utf-8)))
      (assert (string= message receipt))
      (list :consumed receipt :pane (tm:id pane)))))
```
<!-- /example -->

```lisp
(uiop:with-temporary-file (:pathname receipt :keep nil)
  (tm:with-client (client :socket-path *socket-path*)
    (let ((session (find "work" (tm:fetch-sessions client) :key #'tm:name :test #'string=)))
      (drive-worker client session *socket-path* "tmux"
                    (namestring (truename "examples/worker.sh"))
                    (namestring receipt)))))
```

The result contains `:consumed "release #{literal}; λ"` and a pane ID.

- The request travels as literal text; worker arguments travel through argv.
- The worker stays in its pane until the owned daemon stops.
- Receipt paths are local to the daemon host. This is not a remote-file API.

## Inspect a typed failure

Cancel a read before it acquires data, handle `command-cancelled`, and return
the outcome the condition carries:

<!-- example:condition -->
```lisp
(defun cancelled-read (client)
  "Demonstrate typed failure evidence using a read cancelled before acquisition."
  (let ((token (tm:make-cancellation-token)))
    (tm:cancel token)
    (handler-case
        (progn (tm:fetch-snapshot client :cancel-token token)
               (error "A cancelled read unexpectedly completed"))
      (tm:command-cancelled (condition)
        (let ((outcome (tm:error-outcome condition)))
          (list :condition (type-of condition)
                :status (and outcome (tm:outcome-status outcome))
                :phase (and outcome (tm:outcome-phase outcome))))))))
```
<!-- /example -->

```lisp
(tm:with-client (client :socket-path *socket-path*) (cancelled-read client))
```

The handler never retries. Cancelling a mutation after dispatch can give a
different status or phase. See
[command-cancelled](api.md#command-cancelled-type).

## Stop the daemon

Closing a client leaves its daemon alive. The separate
[`kill-server`](api.md#kill-server-function) operation ends a server. This
helper kills only the explicit socket you pass and accepts success only after
the operation proves both dispatch and daemon exit:

<!-- example:termination -->
```lisp
(defun terminate-owned-server (socket-path &key (program "tmux"))
  "Terminate the explicitly selected owned server and return its proven outcome."
  (tm:with-client (client :program program :socket-path socket-path)
    (let ((outcome (tm:kill-server client)))
      (assert (eq :succeeded (tm:outcome-status outcome)))
      (assert (eq :server-terminated (tm:outcome-phase outcome)))
      outcome)))
```
<!-- /example -->

```lisp
(terminate-owned-server *socket-path*)
```

[`stop-daemon`](api.md#stop-daemon-function) then reaps the daemon you started
and removes its socket directory:

```lisp
(tm:stop-daemon *daemon*)
```

Exit the REPL:

```lisp
(uiop:quit)
```
