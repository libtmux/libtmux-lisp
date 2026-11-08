(in-package #:libtmux.internal)

(defun terminal-client-target (target)
  (unless (typep target 'libtmux:attached-client)
    (invalid-argument "Expected a captured attached-client target"))
  (when (libtmux:field-value target :client/control-mode)
    (invalid-argument "This operation requires an ordinary terminal client"))
  ;; Native client lookup strips exactly one final colon.
  (concatenate 'string (libtmux:name target) ":"))

(defun check-terminal-client-selector (target)
  (let* ((name (libtmux:name target))
         (matches
           (remove-if
            (complement
             (lambda (candidate)
               (let ((tty (libtmux:field-value candidate :client/tty)))
                 (or (string= name (libtmux:name candidate))
                     (and tty (or (string= name tty)
                                  (and (uiop:string-prefix-p "/dev/" tty)
                                       (string= name tty :start2 5))))))))
            (libtmux:clients (slot-value target 'libtmux::snapshot)))))
    (unless (and (= 1 (length matches)) (eq target (aref matches 0)))
      (error 'libtmux:stale-target :target target
             :message "The attached-client selector matches another client's name or tty"))))

(defun client-request-builder (arguments)
  (lambda (witness current)
    (declare (ignore witness))
    (terminal-client-target (first current))
    (check-terminal-client-selector (first current))
    arguments))

(defun request-client-action (client target command flags options)
  (let ((arguments (append (list command "-t" (terminal-client-target target)) flags)))
    (apply #'perform-command client (list target) arguments
           :argument-builder (client-request-builder arguments) options)))

(in-package #:libtmux)

(defun switch-client (client target session &key update-environment (observe t)
                                               cancel-token timeout output-limit)
  "Switch captured terminal TARGET to SESSION and return a COMMAND-OUTCOME.
CLIENT is the connection owning both observations. UPDATE-ENVIRONMENT defaults
NIL, preserving the destination session environment; true applies tmux's
update-environment option using TARGET's environment. OBSERVE defaults true and
supplies a replacement attached-client through OUTCOME-VALUE. Earlier captures
stay unchanged; failed follow-up acquisition stays in OUTCOME-OBSERVATION-ERROR.
Blocks for preflight, dispatch and optional observation under shared limits.
Preflight checks the unique client name and PID/creation/tty fingerprint; tmux
does not atomically guard that fingerprint at dispatch. A changed or foreign
target signals STALE-TARGET. Operational failures retain their outcome; no
mutation is retried. Control clients are not supported by this operation.
See also: FETCH-CLIENTS, REFRESH, DETACH-CLIENT, OUTCOME-VALUE."
  (let ((arguments
          (append (list "switch-client" "-c" (libtmux.internal::terminal-client-target target)
                        "-t" (libtmux.internal::physical-target session :session))
                  (unless update-environment '("-E")))))
    (libtmux.internal::perform-command
     client (list target session) arguments
     :argument-builder (libtmux.internal::client-request-builder arguments)
     :observe (when observe (libtmux.internal::observe-target client target))
     :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun detach-client (client target &key cancel-token timeout output-limit)
  "Request detachment of captured terminal TARGET; return a COMMAND-OUTCOME.
CLIENT must own the observation. Success acknowledges the server's request,
not frontend process exit or terminal restoration. Returns no replacement.
Blocks under the supplied limits. The unique name/PID/creation/tty preflight
cannot exclude replacement between validation and dispatch. Missing or foreign
targets signal STALE-TARGET; external failures retain their outcome. Never
retries, detaches other clients, kills a parent, or starts a shell command.
See also: FETCH-CLIENTS, SWITCH-CLIENT, OUTCOME-STATUS."
  (libtmux.internal::request-client-action
   client target "detach-client" nil
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun refresh-client (client target &key status-only cancel-token timeout output-limit)
  "Request a redraw of captured terminal TARGET; return a COMMAND-OUTCOME.
STATUS-ONLY requests only the status line; NIL requests the whole display.
Success acknowledges scheduling, not completed terminal rendering. This is an
external operation; REFRESH instead acquires a replacement observation.
CLIENT must own TARGET. Blocks under shared preflight/dispatch limits. A stale
or foreign target signals STALE-TARGET; other failures retain their outcome.
The client fingerprint is checked before dispatch, with a remaining replacement
race. Returns no replacement and never retries the request.
See also: FETCH-CLIENTS, REFRESH, OUTCOME-STATUS."
  (libtmux.internal::request-client-action
   client target "refresh-client" (when status-only '("-S"))
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun suspend-client (client target &key cancel-token timeout output-limit)
  "Request suspension of captured terminal TARGET; return a COMMAND-OUTCOME.
Tmux asks the frontend to stop with SIGTSTP. Success acknowledges the request;
it does not prove process suspension. An already suspended frontend can be a
no-op. Its controlling application owns resumption. CLIENT must own TARGET.
Blocks under shared preflight/dispatch limits; returns no replacement. Stale or
foreign targets signal STALE-TARGET; other failures retain their outcome.
Preflight cannot exclude client replacement before dispatch. Never retries.
See also: FETCH-CLIENTS, DETACH-CLIENT, LOCK-CLIENT, OUTCOME-STATUS."
  (libtmux.internal::request-client-action
   client target "suspend-client" nil
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun lock-client (client target &key cancel-token timeout output-limit)
  "Request locking of captured terminal TARGET; return a COMMAND-OUTCOME.
The frontend runs the session's configured lock-command through its shell.
Success acknowledges the request, not lock startup, completion or authentication.
An already suspended frontend or an empty/oversized lock command can be a no-op.
CLIENT must own TARGET.
Blocks under shared preflight/dispatch limits; returns no replacement. Stale or
foreign targets signal STALE-TARGET; other failures retain their outcome.
Preflight cannot exclude client replacement before dispatch. Never retries.
See also: FETCH-CLIENTS, SET-OPTION, SUSPEND-CLIENT, OUTCOME-STATUS."
  (libtmux.internal::request-client-action
   client target "lock-client" nil
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))
