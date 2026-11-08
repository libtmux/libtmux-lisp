(in-package #:libtmux.internal)

(defclass libtmux:daemon ()
  ((lock :initform (make-lock "owned tmux daemon"))
   (changed :initform (make-condition-variable))
   (state :initform :starting)
   (program :initarg :program)
   (socket :initform nil)
   (directory :initform nil)
   (directory-identity :initform nil)
   (socket-identity :initform nil)
   (notify :initform nil)
   (watch :initform nil)
   (event :initform nil)
   (job :initform nil)
   (probe-client :initform nil)
   (worker :initform nil)
   (pid :initform nil)
   (process-start :initform nil)
   (startup-active :initform t)
   (stop-requested :initform nil)
   (ready-requested :initform nil)
   (job-wake :initform nil)
   (finished :initform nil)
   (cleanup-owner :initform nil)
   (failure :initform nil)
   (cleanup-failures :initform nil)
   (lifetime-token :initform (libtmux:make-cancellation-token)))
  (:documentation "An explicitly owned foreground tmux daemon and its supervisor.
Create it with START-DAEMON and release it with STOP-DAEMON or WITH-DAEMON.
Ordinary connection clients are separate resources; closing one leaves this
daemon alive. The owner retains failed cleanup work until an explicit retry.
See also: LIBTMUX:START-DAEMON, LIBTMUX:STOP-DAEMON, LIBTMUX:WITH-DAEMON."))

(defun call-with-daemon-lock (owner function)
  (call-with-lock (slot-value owner 'lock) function))

(defun call-with-daemon-scope (owner function)
  (let ((normal nil))
    (unwind-protect
         (multiple-value-prog1 (funcall function owner) (setf normal t))
      (handler-case (libtmux:stop-daemon owner)
        (error (condition)
          (if normal (error condition)
              (retain-daemon-cleanup-failure owner condition)))))))

(defmethod print-object ((owner libtmux:daemon) stream)
  (print-unreadable-object (owner stream :type t :identity t)
    (write-string (symbol-name (libtmux:daemon-state owner)) stream)))

(in-package #:libtmux)

(defgeneric error-daemon (condition)
  (:documentation "Return the daemon owner retained by a startup or cleanup failure.
The owner may need STOP-DAEMON even when START-DAEMON did not return. No I/O.
See also: DAEMON-START-FAILED, DAEMON-CLEANUP-FAILED, PENDING-DAEMON-CLEANUPS."))

(define-condition daemon-start-failed (libtmux-error)
  ((daemon :initarg :daemon :reader error-daemon))
  (:documentation "Managed startup failed; ERROR-CAUSE and ERROR-DAEMON retain evidence.
Startup attempts cleanup before propagating this condition. Incomplete cleanup
also remains discoverable through PENDING-DAEMON-CLEANUPS.
See also: ERROR-DAEMON, ERROR-CAUSE, STOP-DAEMON."))

(define-condition daemon-cleanup-failed (cleanup-failed)
  ((resource :initarg :resource :reader error-daemon))
  (:documentation "Owned daemon cleanup is incomplete and remains retryable.
ERROR-DAEMON retains the owner. Inspect DAEMON-CLEANUP-FAILURES and retry
STOP-DAEMON; no replacement daemon is started.
See also: ERROR-DAEMON, DAEMON-CLEANUP-FAILURES, STOP-DAEMON."))

(defun daemon-state (daemon)
  "Return DAEMON's observed lifecycle state without I/O.
States are :STARTING, :READY, :STOPPING, :FAILED and :CLOSED. READY records
completed startup verification, not a promise of future process liveness.
See also: DAEMON-FAILURE, STOP-DAEMON."
  (libtmux.internal::call-with-daemon-lock
   daemon (lambda () (slot-value daemon 'libtmux.internal::state))))

(defun daemon-program (daemon)
  "Return an owned copy of DAEMON's resolved tmux executable path. No I/O.
Pass it as OPEN-CLIENT's :PROGRAM when connecting through DAEMON-SOCKET-PATH.
See also: DAEMON-SOCKET-PATH, OPEN-CLIENT."
  (copy-seq (slot-value daemon 'libtmux.internal::program)))

(defun daemon-socket-path (daemon)
  "Return an owned copy of DAEMON's private socket path, or NIL before allocation.
No I/O. An ordinary client may connect while the owner is READY. Closing that
client leaves the daemon alive; STOP-DAEMON releases the daemon itself.
See also: DAEMON-PROGRAM, OPEN-CLIENT, STOP-DAEMON."
  (let ((path (slot-value daemon 'libtmux.internal::socket)))
    (and path (copy-seq path))))

(defun daemon-failure (daemon)
  "Return DAEMON's retained primary failure condition, or NIL. No I/O.
This shared diagnostic can describe background failure after startup returned.
See also: DAEMON-STATE, DAEMON-CLEANUP-FAILURES."
  (libtmux.internal::call-with-daemon-lock
   daemon (lambda () (slot-value daemon 'libtmux.internal::failure))))

(defun daemon-cleanup-failures (daemon)
  "Return a fresh vector of retained secondary cleanup conditions. No I/O.
Conditions are shared diagnostics, newest first, bounded to sixteen entries.
See also: STOP-DAEMON, DAEMON-FAILURE, PENDING-DAEMON-CLEANUPS."
  (libtmux.internal::call-with-daemon-lock
   daemon (lambda () (coerce (slot-value daemon 'libtmux.internal::cleanup-failures)
                             'simple-vector))))

(defun pending-daemon-cleanups ()
  "Return a fresh vector of owners with incomplete cleanup, without daemon I/O.
The library retains them even when startup leaves through a nonlocal exit.
Successful STOP-DAEMON removes an owner from this collection.
See also: STOP-DAEMON, ERROR-DAEMON."
  (libtmux.internal::require-process-profile)
  (libtmux.internal::pending-daemon-owners))

(defun start-daemon (&key (program "tmux") (environment nil environment-p)
                          working-directory temporary-directory
                          (timeout 30) (output-limit 1048576) cancel-token)
  "Start an owned empty-config daemon on a fresh private socket and await readiness.
Uses the qualified SBCL/Linux backend and explicit /dev/null configuration.
ENVIRONMENT is a finite list/vector of distinct NAME=VALUE strings; omission
copies the caller environment, and NIL selects an empty input environment.
Tmux selectors, socket activation and launcher controls are removed. Caller
locale is preserved; Bash shell metadata is not byte-transparent. Environment
values and the native executable remain trusted application configuration.
WORKING-DIRECTORY defaults to the captured current directory. The owner creates
a fresh directory under TEMPORARY-DIRECTORY (default UIOP's temporary directory).
Its canonical ancestors must be owned by this user or root; writable ancestors
must have the sticky bit. No existing daemon or endpoint is adopted.
TIMEOUT is one startup deadline after input preparation, including version and
readiness IPC. OUTPUT-LIMIT must be at least two bytes: half bounds daemon
lifetime diagnostics; the remainder bounds version/readiness output. Cleanup
adds bounded waits; synchronous setup and scheduling can extend caller wall time.
CANCEL-TOKEN affects startup only; after READY, STOP-DAEMON owns cancellation.
Signals DAEMON-START-FAILED with the original cause and owner on startup failure.
See also: WITH-DAEMON, STOP-DAEMON, ERROR-DAEMON, OPEN-CLIENT."
  (libtmux.internal::require-process-profile)
  (libtmux.internal::start-managed-daemon
   program environment environment-p working-directory temporary-directory
   timeout output-limit cancel-token))

(defun stop-daemon (daemon)
  "Stop and reap DAEMON's owned child, then remove its checked socket and directory.
Idempotent after success; returns no values. Never targets a daemon through a
reusable PID or socket command. A 0.75-second admission wait and a separate
0.75-second worker join precede any retried job cleanup (up to 0.5 seconds).
Synchronous OS calls and scheduling can extend wall time. Failed cleanup signals
DAEMON-CLEANUP-FAILED and retains the owner for retry. Closing an ordinary client
does not call this function. Terminating the daemon does not establish exit of
every pane descendant.
See also: WITH-DAEMON, DAEMON-CLEANUP-FAILURES, PENDING-DAEMON-CLEANUPS."
  (libtmux.internal::require-process-profile)
  (check-type daemon daemon)
  (libtmux.internal::stop-managed-daemon daemon))

(defmacro with-daemon ((name &rest options) &body body)
  "Bind a newly started daemon and stop the original owner on every exit.
Accepts START-DAEMON keyword options and body declarations. Preserves multiple
values and the primary nonlocal exit. A cleanup failure after normal completion
signals; during an existing exit it is retained for explicit inspection/retry.
See also: START-DAEMON, STOP-DAEMON, PENDING-DAEMON-CLEANUPS."
  (let ((owner (gensym "DAEMON")))
    `(let ((,owner (start-daemon ,@options)))
       (libtmux.internal::call-with-daemon-scope ,owner (lambda (,name) ,@body)))))
