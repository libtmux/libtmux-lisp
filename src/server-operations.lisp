(in-package #:libtmux)

(defun display-message (client message &key target format-p cancel-token timeout output-limit)
  "Print MESSAGE through tmux; return owned UTF-8 text and a COMMAND-OUTCOME.
Always uses the ordinary -p printer, preserving its whitespace and trailing lines.
Native versions can escape output, so it is not a byte-identical echo. MESSAGE
is literal by default. FORMAT-P enables tmux format and time expansion;
#() may start shell jobs but does not wait for their output. Fresh requests can
print empty or incomplete job results. The native command client owns those
jobs; its disconnect cleans them up.

TARGET may be a captured session, window, pane or window-link owned by CLIENT.
Use a window-link for exact session/index context. With no target, tmux selects
the context; physical windows and panes also leave their session context to
tmux. Foreign, replaced or vanished targets signal STALE-TARGET.

The result includes after-hook printer output; it is not a decoded scalar or
configuration record. Hooks may also have effects. The call blocks under shared
preflight/dispatch limits, acquires no replacement and never retries. Tmux 3.3a
literal fallback limits the escaped intermediate text to 8,191 UTF-8 bytes;
newer daemons use native literal printing. Encoded command limits also apply.
Invalid UTF-8 signals DECODING-ERROR with its outcome; other failures retain
their diagnostic outcome. Local validation signals INVALID-ARGUMENT.
See also: RUN-COMMAND, CAPTURE-PANE, SET-HOOK, OUTCOME-STDOUT, ERROR-OUTCOME."
  (let* ((message (libtmux.internal::text-argument message "Message"))
         (locator (when target
                    (unless (typep target '(or session window pane window-link))
                      (libtmux.internal::invalid-argument
                       "Message target must be a captured session, window, pane or window-link"))
                    (libtmux.internal::target-guard target)))
         (prefix (append '("display-message" "-p") (when locator (list "-t" locator))))
         (outcome
           (libtmux.internal::perform-command
            client (when target (list target)) (append prefix (list "--" message))
            :argument-builder
            (lambda (witness current)
              (declare (ignore current))
              (let ((literal-flag (and (not format-p)
                                       (libtmux.internal::version-at-least-p
                                        (libtmux.internal::server-witness-version witness) "3.4"))))
                (append prefix (when literal-flag '("-l"))
                        (list "--" (if (or format-p literal-flag)
                                       message
                                       (libtmux.internal::literal-time-format message))))))
            :cancel-token cancel-token :timeout timeout :output-limit output-limit)))
    (handler-bind ((decoding-error (lambda (condition) (setf (slot-value condition 'client) client))))
      (values (libtmux.internal::outcome-text outcome) outcome))))

(defun lock-session (client session &key cancel-token timeout output-limit)
  "Request locking of SESSION's attached frontends; return a COMMAND-OUTCOME.
CLIENT must own the captured SESSION. The live session membership determines
which frontends receive the request. Each runs its configured lock-command;
control clients, suspended frontends and empty/oversized commands are skipped.
Success acknowledges the request, not startup, completion or authentication.
Blocks under shared preflight/dispatch limits and returns no replacement.
Foreign or vanished sessions signal STALE-TARGET; other failures retain their
outcome. Lock programs belong to the frontends; closing CLIENT leaves them
running. Never retries.
See also: LOCK-CLIENT, LOCK-SERVER, SET-OPTION, OUTCOME-STATUS, ERROR-OUTCOME."
  (libtmux.internal::perform-command
   client (list session)
   (list "lock-session" "-t" (libtmux.internal::physical-target session :session))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun lock-server (client &key cancel-token timeout output-limit)
  "Request locking of all attached frontends on CLIENT's daemon.
Return a COMMAND-OUTCOME after guarded dispatch. Live frontend membership
determines the recipients; this is wider than one captured session. Each
frontend runs its configured lock-command. Control clients, suspended
frontends and empty/oversized commands are skipped. Success acknowledges
the request, not startup, completion or authentication. Blocks under shared
preflight/dispatch limits and returns no replacement. Failures retain their
outcome. Lock programs belong to the frontends; closing CLIENT leaves them
running. Never retries.
See also: LOCK-CLIENT, LOCK-SESSION, SET-OPTION, OUTCOME-STATUS, ERROR-OUTCOME."
  (libtmux.internal::perform-command
   client nil '("lock-server")
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun wait-for (client channel &key (operation :wait) cancel-token timeout output-limit)
  "Wait, signal, lock or unlock the literal CHANNEL; return a COMMAND-OUTCOME.
OPERATION is :WAIT (default), :SIGNAL, :LOCK or :UNLOCK. CHANNEL is a nonempty
string without NUL. This call performs I/O on an existing daemon. :WAIT and
:LOCK require tmux 3.8, whose client-loss handling removes queued waiters;
older daemons signal UNSUPPORTED-CAPABILITY before dispatch. :SIGNAL and
:UNLOCK support the library's tmux floor.

A signal wakes current waiters or retains one pending wake. Repeated signals
are not an idempotent latch or a counting semaphore. Locks have no owner and
survive this call and CLOSE-CLIENT within the daemon's lifetime; unlock them
explicitly. Continuation does not identify a sender; server shutdown can flush
waiting requests. Signals and locks
share a channel, so applications should use separate names for those protocols.

One operation owns CLIENT at a time. Use another client to signal or unlock
a blocked call. TIMEOUT and OUTPUT-LIMIT cover preflight and waiting together.
Cancellation or lost acknowledgement can leave signal consumption or a lock
grant uncertain; inspect ERROR-OUTCOME. Never retries or unlocks automatically.
Signals INVALID-ARGUMENT, COMMAND-FAILED or an operational condition.
See also: CLOSE-CLIENT, CANCEL, ERROR-OUTCOME, OUTCOME-STATUS, UNSUPPORTED-CAPABILITY."
  (let* ((channel (libtmux.internal::text-argument channel "Wait channel" nil))
         (flag (case operation
                 (:wait nil) (:signal "-S") (:lock "-L") (:unlock "-U")
                 (otherwise
                  (libtmux.internal::invalid-argument
                   "Wait operation must be :wait, :signal, :lock or :unlock"))))
         (blocking (member operation '(:wait :lock))))
    (libtmux.internal::perform-command
     client nil (append (list "wait-for") (when flag (list flag)) (list "--" channel))
     :minimum-version (when blocking "3.8") :feature :wait-channel-disconnect-cleanup
     :cancel-token cancel-token :timeout timeout :output-limit output-limit)))
