# Capture, inspect and build a workspace

This tutorial uses an isolated existing tmux daemon. It creates two sessions,
three physical windows, four links and four panes, then inspects them through
ordinary Common Lisp data. It modifies only the daemon you start below.
Complete the [source installation](../README.md#install-from-source) first.

## Run the checked walkthrough

```console
$ mise run examples
```

The runner creates a mode-0700 temporary directory and explicit socket, clears
inherited tmux variables, starts an empty-configuration daemon, runs the shipped
Lisp examples, checks their results and terminates its own server. Assertions
check object/link counts, false with presence, identity, ownership, literal
names, refresh, byte buffers, optional regex/JSON queries and local access after
client closure. A failure exits nonzero. It leaves the optional thread library
unloaded.

Select another native tmux binary explicitly:

```console
$ LIBTMUX_TEST_TMUX=/usr/bin/tmux mise run examples
```

## Work at the REPL

For an interactive session, create a private daemon in a shell and keep that
shell open. This command prints its socket path; use that path when prompted
in Lisp. The automated runner and final cleanup helper need Python 3; the
library itself does not.

```console
$ export LIBTMUX_DEMO_DIR="$(mktemp -d /tmp/libtmux-lisp-demo-XXXXXXXX)" && \
  env -u TMUX \
    -u TMUX_PANE \
    tmux \
      -S "$LIBTMUX_DEMO_DIR/tmux.sock" \
      -f /dev/null \
      new-session \
        -d \
        -s work \
        -n editor \
        -x 120 \
        -y 40 \
        -- /bin/cat && \
  printf '%s\n' "$LIBTMUX_DEMO_DIR/tmux.sock"
```

Use the same terminal to start the pinned REPL:

```console
$ mise run repl
```

Load the query system, which depends on the core. The development REPL
registers the ASDF definition but does not implicitly load either system:

```lisp
(asdf:load-system "libtmux/query")
```

Load the two optional query integrations used later in the checked walkthrough:

```lisp
(asdf:load-system "libtmux/regex")
```

```lisp
(asdf:load-system "libtmux/json")
```

Load the recipe functions. Their package declares the SBCL package-local
nicknames `tm`, `q` and `j` for the core, query and JSON packages; the library
claims no global short nicknames.

```lisp
(load "examples/workspace.lisp")
```

```lisp
(in-package #:libtmux.examples)
```

Supply the printed socket path as data, without invoking the Lisp reader:

```lisp
(defparameter *socket-path* (progn (write-line "Paste the demo socket path:")
                                 (read-line)))
```

This acquires the graph and returns one session record named `work`, containing
its `editor` window and one pane. Pane projections include identity, captured
fields, provenance and relationship IDs:

```lisp
(inspect-workspace *socket-path*)
```

## Build a linked workspace

The complete recipe is copied from [workspace.lisp](../examples/workspace.lisp).
It creates a `logs` window and `review` session, splits `editor`, shares that
physical window through index 7 of `review`, and renames logs literally.
Run it once on the fresh demo; a repeated invocation encounters existing names.

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

Keep a captured graph after closing the client. These globals are interactive
scratch values, not a global connection convention in the library:

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

The result is `(2 3 4 4)`. The two editor links have different session/index
locators and the same physical window. `windows` on a snapshot deduplicates
physical windows; `windows` on a session retains one entry per link.
The [graph contract](captures.md) explains all traversal directions.

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

This returns a nonempty list of plists from the retained graph. You can instead
use `map`, `find-if`, `count-if`, `reduce` or `remove-if` with a native function.
These calls do not acquire state.

Compile a reusable scalar filter when the selection should be validated,
inspected or shared. The example package's local nickname `q` refers to
`libtmux.query`; the library claims no global nickname.

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

`matching` returns a fresh simple vector in captured order. Compilation copies
the query form and checks field types, cycles and resource limits. The returned
predicate is ordinary Lisp code over retained observations; neither compilation
nor matching contacts tmux.

Traverse registered relationships without reacquiring state, and keep the eager
selection in a QuerySet with explicit root-model metadata:

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

See the [native query guide](queries.md) for quantifier identities, stable
ordering, ownership and strict cardinality.

## Match and serialize an optional query

`libtmux/regex` adds CL-PPCRE-backed operators without adding that dependency
to core or `libtmux/query`. The scanner is compiled once with the filter; this
full-match example also proves that a match beginning at position zero works:

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

`libtmux/json` writes the native schema `libtmux.lisp.filter/1`. Reading regex
is an explicit local opt-in because parser limits do not interrupt CL-PPCRE
scanner execution:

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

Both operations are local. The [interchange guide](query-interchange.md)
documents the closed envelope, limits and false/empty/null distinctions.

Use both values when false and absence matter. This field is always present;
an inactive pane returns `nil` and `t`:

```lisp
(let ((pane (find-if-not #'tm:active-p (tm:panes *snapshot*))))
  (multiple-value-bind (value present-p) (tm:field-value pane :pane/active)
    (list value present-p)))
```

Returned strings, plists and relation vectors are caller-owned copies.
`entity-data` is finite and contains relationship identifiers rather than a
recursive graph. A copied plist is local data; editing it does not mutate tmux.
See the [field reference](fields.md) for types and optional values.

## Handle command and observation outcomes

Creation and named mutations return
[command-outcome](api.md#command-outcome-type). A successful command
can have no replacement observation because the target disappeared afterward.
Check the observation separately; this helper never retries the mutation:

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

Rename a captured physical window and inspect old and new observations:

```lisp
(tm:with-client (client :socket-path *socket-path*)
  (let* ((snapshot (tm:fetch-snapshot client))
         (window (find "editor" (tm:windows snapshot) :key #'tm:name :test #'string=))
         (renamed (observed-value (tm:rename-window client window "api #{literal}"))))
    (list (tm:name window) (tm:name renamed) (tm:same-entity-p window renamed))))
```

The result is `("editor" "api #{literal}" t)`. The literal format punctuation
survives. Refresh uses the **same client context** and returns another captured
observation. Observations from a different connection are not interchangeable
operational targets, even when their numeric IDs match.

External failures signal typed conditions. A handler can inspect
[error-outcome](api.md#error-outcome-function),
[outcome-status](api.md#outcome-status-function),
[outcome-phase](api.md#outcome-phase-function),
[outcome-exit-code](api.md#outcome-exit-code-function) and owned
diagnostic bytes. Missing completion evidence can mean the mutation already
happened; an automatic retry can duplicate effects. The
[operation guide](operations.md#outcomes-and-target-checks) defines these cases.

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

This returns five octets, including NUL and invalid UTF-8, unchanged. For pane
contents, `capture-pane` returns UTF-8 text and outcome; use
`capture-pane-bytes` for octets. Captures and buffer reads are bounded complete
results, not subscriptions or streams.

Successful input dispatch does not prove application readiness or consumption.
Coordinate with an application signal; do not add a sleep or treat printed
text as proof. `pipe-pane` configures a daemon-owned shell pipe and has a
separate [ownership contract](operations.md#pane-processes).

## Drive an application without polling

The shipped [worker](../examples/worker.sh) signals initialization, reads one
request, writes its receipt file, then signals consumption. The Lisp controller
uses a fresh `wait-for` channel for each signal. The file receipt proves what
the application consumed; a successful send or printed marker would not.
These are blocking calls with deadlines, not a control-mode subscription API.

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
(tm:with-client (client :socket-path *socket-path*)
  (let ((session (find "work" (tm:fetch-sessions client) :key #'tm:name :test #'string=)))
    (drive-worker client session *socket-path* "tmux"
                  (namestring (truename "examples/worker.sh"))
                  (namestring (merge-pathnames "worker-receipt.txt"
                               (uiop:pathname-directory-pathname *socket-path*))))))
```

The result contains `:consumed "release #{literal}; λ"` and a pane ID. The
request travels as literal text; worker arguments travel through argv. The
worker remains in its pane until the owned daemon is stopped. Receipt paths
are local to this example's daemon host; this is not a remote-file API.

## Inspect a typed failure

This cancels a read before it acquires data, then handles `command-cancelled`
and returns the retained dispatch evidence:

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

This handler inspects evidence and returns; it never retries a command.
Post-dispatch cancellation of a mutation can have a different status or phase.
See the [condition reference](api.md#command-cancelled-type).

## Clean up

Exit the REPL:

```lisp
(uiop:quit)
```

In the original shell, terminate only the daemon created for this tutorial:

```console
$ python3 tools/stop-example.py "$LIBTMUX_DEMO_DIR"
```

The helper sends `kill-server` to the explicit demo endpoint, waits for its
daemon to exit through a Linux pidfd, then removes the owned receipt and stale
socket file. Tmux 3.3a can leave its socket behind after exit.
Closing a library client leaves the daemon and its panes alive. Server
termination is a separate step here; a named lifecycle API is unfinished.
