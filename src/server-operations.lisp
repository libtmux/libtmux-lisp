(in-package #:libtmux)

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
