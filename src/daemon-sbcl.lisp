(in-package #:libtmux.internal)

(sb-alien:define-alien-routine ("inotify_init1" notify-open) sb-alien:int
  (flags sb-alien:int))
(sb-alien:define-alien-routine ("inotify_add_watch" notify-watch) sb-alien:int
  (fd sb-alien:int) (path sb-alien:c-string) (mask sb-alien:unsigned-int))

(defvar *pending-daemon-owners* nil)
(defvar *pending-daemon-lock* (make-lock "pending daemon cleanups"))
(defvar *daemon-stage-hook* nil)

(defun pending-daemon-owners ()
  (call-with-lock *pending-daemon-lock*
                  (lambda () (coerce *pending-daemon-owners* 'simple-vector))))

(defun retain-daemon-owner (owner)
  (call-with-lock *pending-daemon-lock*
                  (lambda () (pushnew owner *pending-daemon-owners*))))

(defun forget-daemon-owner (owner)
  (call-with-lock *pending-daemon-lock*
                  (lambda () (setf *pending-daemon-owners*
                                    (remove owner *pending-daemon-owners*)))))

(defun retain-daemon-cleanup-failure (owner condition)
  (call-with-daemon-lock
   owner (lambda ()
           (setf (slot-value owner 'cleanup-failures)
                 (subseq (cons condition (slot-value owner 'cleanup-failures))
                         0 (min 16 (1+ (length (slot-value owner 'cleanup-failures))))))))
  (retain-daemon-owner owner))

(defun daemon-stage (stage owner)
  (when *daemon-stage-hook* (funcall *daemon-stage-hook* stage owner)))

(defun bootstrap-environment (environment)
  (remove-if
   (lambda (entry)
     (member (subseq entry 0 (position #\= entry))
             '("TMUX" "TMUX_PANE" "TMUX_TMPDIR" "LISTEN_PID" "LISTEN_FDS"
               "LISTEN_FDNAMES" "BASH_COMPAT" "BASH_XTRACEFD")
             :test #'string=))
   (owned-process-environment environment)))

(defun bootstrap-parent (directory)
  (let* ((parent (canonical-native-path (owned-working-directory directory)))
         (path (string-right-trim "/" parent)))
    (loop
      for current = (if (string= path "") "/" path)
      for stat = (sb-posix:lstat current)
      do (unless (and (sb-posix:s-isdir (sb-posix:stat-mode stat))
                      (member (sb-posix:stat-uid stat) (list 0 (sb-posix:geteuid)))
                      (or (zerop (logand #o22 (sb-posix:stat-mode stat)))
                          (logtest #o1000 (sb-posix:stat-mode stat))))
           (invalid-argument "Daemon temporary parent requires trusted owners and protected writable directories"))
         (when (string= current "/") (return parent))
         (setf path (subseq path 0 (position #\/ path :from-end t))))))

(defun daemon-file-identity (path type)
  (handler-case
      (let ((stat (sb-posix:lstat path)))
        (unless (ecase type
                  (:socket (sb-posix:s-issock (sb-posix:stat-mode stat)))
                  (:directory (sb-posix:s-isdir (sb-posix:stat-mode stat))))
          (error 'libtmux:cleanup-failed :message "Owned daemon path has an unexpected file type"))
        (list (sb-posix:stat-dev stat) (sb-posix:stat-ino stat)))
    (sb-posix:syscall-error (condition)
      (if (= (sb-posix:syscall-errno condition) sb-posix:enoent) nil (error condition)))))

(defun wake-daemon-waiters (owner)
  (when (slot-value owner 'event) (wake-operation (slot-value owner 'event)))
  (condition-broadcast (slot-value owner 'changed)))

(defun daemon-startup-check (owner budget token)
  (call-with-daemon-lock
   owner (lambda ()
           (unless (eq (slot-value owner 'state) :ready)
             (check-capture-budget budget token)
             (when (slot-value owner 'failure) (error (slot-value owner 'failure)))
             (when (or (slot-value owner 'finished) (slot-value owner 'stop-requested))
               (error 'libtmux:command-failed :message "Owned daemon stopped during startup"))))))

(defun daemon-notify-u32 (bytes offset)
  (loop for i below 4 sum (ash (aref bytes (+ offset i)) (* 8 i))))

(defun read-daemon-notifications (owner)
  (let* ((bytes (make-array 4096 :element-type '(unsigned-byte 8)))
         (fd (slot-value owner 'notify))
         (count (handler-case
                    (sb-sys:with-pinned-objects (bytes)
                      (sb-posix:read fd (sb-sys:vector-sap bytes) (length bytes)))
                  (sb-posix:syscall-error (condition)
                    (if (member (sb-posix:syscall-errno condition)
                                (list sb-posix:eagain sb-posix:eintr))
                        0 (error condition)))))
         (found nil))
    (loop for offset = 0 then end
          while (< offset count)
          for header = (if (<= (+ offset 16) count) offset
                           (error 'libtmux:decoding-error :message "Truncated daemon watch event"))
          for watch = (daemon-notify-u32 bytes header)
          for mask = (daemon-notify-u32 bytes (+ offset 4))
          for size = (daemon-notify-u32 bytes (+ offset 12))
          for start = (+ offset 16)
          for end = (+ start size)
          do (unless (and (<= end count) (zerop (mod size 4)) (zerop (logand mask #xec00))
                          (= watch (slot-value owner 'watch)))
               (error 'libtmux:command-failed :message "Daemon startup watch was lost or invalid"))
             (when (and (logtest 4 mask) (>= size 7)
                        (equalp #(115 111 99 107 101 116 0) (subseq bytes start (+ start 7))))
               (let ((identity (daemon-file-identity (slot-value owner 'socket) :socket)))
                 (unless identity
                   (error 'libtmux:command-failed :message "Daemon socket disappeared before readiness"))
                 (setf (slot-value owner 'socket-identity) identity found t))))
    found))

(defun await-daemon-socket (owner budget token)
  (loop
    (let ((ready (poll-owned
                  (list (list :watch (slot-value owner 'notify) :input)
                        (list :state (slot-value owner 'event) :input))
                  (max 0 (- (capture-budget-deadline budget) (monotonic-seconds))))))
      (when (member :watch ready)
        (when (read-daemon-notifications owner)
          (daemon-startup-check owner budget token)
          (return)))
      (when (member :state ready) (consume-wake (slot-value owner 'event)))
      (daemon-startup-check owner budget token))))

(defun commit-daemon-ready (owner job)
  ;; The worker owns JOB. The owner lock excludes close and wake retirement;
  ;; the token lock makes cancellation and gate-to-lifetime transfer exclusive.
  (let ((startup (process-job-token job))
        (lifetime (slot-value owner 'lifetime-token)))
    (call-with-lock
     (slot-value startup 'libtmux::lock)
     (lambda ()
       (when (slot-value startup 'libtmux::cancelled-p)
         (error 'libtmux:command-cancelled :message "Daemon startup was cancelled"))
       (unless (and (< (monotonic-seconds) (process-job-deadline job))
                    (process-job-released job) (not (process-job-terminal job))
                    (not (process-job-reason job))
                    (null (poll-owned (list (list :child (process-job-pidfd job) :input)) 0)))
         (error 'libtmux:command-failed :message "Owned daemon is not live at readiness handoff"))
       (let ((old (remove (process-job-wake job) (slot-value startup 'libtmux::registrations)))
             (new (list (process-job-wake job))))
         (sb-sys:without-interrupts
           (setf (slot-value startup 'libtmux::registrations) old
                 (slot-value lifetime 'libtmux::registrations) new
                 (process-job-token job) lifetime
                 (process-job-deadline job) nil
                 (slot-value owner 'state) :ready)))))))

(defun daemon-supervisor-step (owner job)
  (when (call-with-daemon-lock
         owner (lambda () (and (slot-value owner 'ready-requested)
                               (eq (slot-value owner 'state) :starting))))
    (daemon-stage :before-ready owner))
  (let ((stop
          (call-with-daemon-lock
           owner (lambda ()
                   (cond ((slot-value owner 'stop-requested) t)
                         ((and (slot-value owner 'ready-requested)
                               (eq (slot-value owner 'state) :starting))
                          (commit-daemon-ready owner job)
                          (wake-daemon-waiters owner)
                          nil))))))
    (when stop (stop-job job :owner-close))))

(defun daemon-job-failure (job)
  (make-condition 'libtmux:command-failed
                  :outcome (process-job-outcome job)
                  :message (format nil "Owned daemon exited (~A, ~A)"
                                   (process-job-reason job) (process-job-code job))))

(defun supervise-daemon (owner)
  (let ((job (slot-value owner 'job)) (failure nil))
    (unwind-protect
         (handler-case
             (progn
               (when (acquire-job job)
                 (call-with-daemon-lock
                  owner (lambda ()
                          (setf (slot-value owner 'job-wake) (process-job-wake job))
                          (when (process-job-process job)
                            (setf (slot-value owner 'pid)
                                  (uiop:process-info-pid (process-job-process job))
                                  (slot-value owner 'process-start)
                                  (linux-process-start (slot-value owner 'pid))))))
                 (daemon-stage :gated owner)
                 (supervise-job job :before-step
                                (lambda (owned) (daemon-supervisor-step owner owned))))
               (unless (slot-value owner 'stop-requested)
                 (setf failure (daemon-job-failure job))))
           (error (condition) (setf failure condition)))
      ;; Publish before cleanup can close the wake descriptor. Parent writers
      ;; perform their entire write while holding this same lock.
      (call-with-daemon-lock
       owner (lambda ()
               (setf (slot-value owner 'job-wake) nil
                     (slot-value owner 'state) (if failure :failed :stopping)
                     (slot-value owner 'failure) (or failure (slot-value owner 'failure)))
               (handler-case (wake-daemon-waiters owner)
                 (error (condition)
                   (setf failure (or failure condition)
                         (slot-value owner 'failure) (or (slot-value owner 'failure) condition))))))
      (unwind-protect
           (unless (cleanup-job job) (retain-daemon-owner owner))
        (dolist (condition (process-job-cleanup-failures job))
          (retain-daemon-cleanup-failure owner condition))
        (call-with-daemon-lock
         owner (lambda ()
                 (setf (slot-value owner 'finished) t)
                 (handler-case (wake-daemon-waiters owner)
                   (error (condition)
                     (setf failure (or failure condition)
                           (slot-value owner 'failure) (or (slot-value owner 'failure) condition))))))
        (when failure (retain-daemon-owner owner))))))

(defun run-daemon-supervisor (owner)
  (handler-case (supervise-daemon owner)
    (error (condition)
      (call-with-daemon-lock
       owner (lambda ()
               (setf (slot-value owner 'state) :failed
                     (slot-value owner 'job-wake) nil
                     (slot-value owner 'finished) t
                     (slot-value owner 'failure) (or (slot-value owner 'failure) condition))
               (handler-case (wake-daemon-waiters owner)
                 (error () (condition-broadcast (slot-value owner 'changed))))))
      (retain-daemon-cleanup-failure owner condition))))

(defun allocate-daemon-endpoint (owner parent)
  (setf (slot-value owner 'directory)
        (sb-posix:mkdtemp
         (concatenate 'string (string-right-trim "/" parent) "/libtmux-lisp-daemon-XXXXXX")))
  (setf (slot-value owner 'directory-identity)
        (daemon-file-identity (slot-value owner 'directory) :directory)
        (slot-value owner 'socket) (concatenate 'string (slot-value owner 'directory) "/socket"))
  (sb-posix:chmod (slot-value owner 'directory) #o700)
  (when (> (length (encode-utf8 (slot-value owner 'socket))) 107)
    (invalid-argument "Temporary directory leaves insufficient space for a Unix socket path"))
  (setf (slot-value owner 'event) (cancellation-event-open))
  (when (minusp (slot-value owner 'event))
    (setf (slot-value owner 'event) nil)
    (error 'libtmux:command-failed :message "Cannot allocate daemon lifecycle event"))
  (setf (slot-value owner 'notify) (notify-open (logior #o2000000 sb-posix:o-nonblock)))
  (when (minusp (slot-value owner 'notify))
    (setf (slot-value owner 'notify) nil)
    (error 'libtmux:unsupported-platform :feature :inotify
           :message "Managed startup requires Linux inotify"))
  (let ((watch (notify-watch (slot-value owner 'notify) (slot-value owner 'directory) #xc04)))
    (when (minusp watch)
      (error 'libtmux:command-failed :message "Cannot watch the private daemon directory"))
    (setf (slot-value owner 'watch) watch)))

(defun verify-daemon-ready (owner client budget token)
  (daemon-startup-check owner budget token)
  (let ((witness (call-with-operation
                  client token (lambda (owned-token) (read-server-witness client owned-token budget)))))
    (unwind-protect
         (unless (and (= (server-witness-pid witness) (slot-value owner 'pid))
                      (= (server-witness-process-start witness) (slot-value owner 'process-start))
                      (string= (server-witness-version witness) (slot-value client 'libtmux::version))
                      (equal (list (server-witness-device witness) (server-witness-inode witness))
                             (slot-value owner 'socket-identity))
                      (equal (slot-value owner 'socket-identity)
                             (daemon-file-identity (slot-value owner 'socket) :socket)))
           (error 'libtmux:command-failed :message "Readiness IPC did not identify the owned daemon"))
      (close-witness witness))))

(defun request-daemon-ready (owner budget token)
  (daemon-startup-check owner budget token)
  (call-with-daemon-lock
   owner (lambda ()
           (unless (and (eq (slot-value owner 'state) :starting) (slot-value owner 'job-wake))
             (error 'libtmux:command-failed :message "Daemon supervisor stopped before readiness"))
           (setf (slot-value owner 'ready-requested) t)
           (wake-operation (slot-value owner 'job-wake))))
  (loop
    (when (eq (libtmux:daemon-state owner) :ready) (return))
    (daemon-startup-check owner budget token)
    (poll-owned (list (list :state (slot-value owner 'event) :input))
                (max 0 (- (capture-budget-deadline budget) (monotonic-seconds))))
    (consume-wake (slot-value owner 'event))))

(defun start-managed-daemon (program environment environment-p working-directory parent
                            timeout output-limit cancel-token)
  (check-limits timeout output-limit)
  (when (< output-limit 2) (invalid-argument "Daemon output limit must be at least two bytes"))
  (ensure-process-platform)
  (let* ((program (native-program program))
         (environment (bootstrap-environment (if environment-p environment (sb-ext:posix-environ))))
         (cwd (owned-working-directory (or working-directory (sb-ext:native-namestring (uiop:getcwd)))))
         (parent (bootstrap-parent (or parent (sb-ext:native-namestring (uiop:temporary-directory)))))
         (token (or cancel-token (libtmux:make-cancellation-token)))
         (owner (make-instance 'libtmux:daemon :program program))
         (start (monotonic-seconds))
         (diagnostics (floor output-limit 2))
         (budget (make-capture-budget :start start :deadline (+ start timeout)
                                      :remaining (- output-limit diagnostics)
                                      :row-limit 1 :field-limit 65536))
         (returned nil) (primary nil))
    (check-type token libtmux:cancellation-token)
    (unwind-protect
         (handler-case
             (progn
               (setf (slot-value owner 'probe-client)
                     (make-instance 'libtmux:client :program program))
               (let* ((client (slot-value owner 'probe-client))
                      (outcome (call-with-operation
                                client token (lambda (owned-token)
                                               (execute-capture-command client '("-V") owned-token budget))))
                      (version (string-trim '(#\Newline #\Return)
                                            (strict-text (libtmux:outcome-stdout outcome)))))
                 (unless (and (>= (length version) 5) (string= "tmux " version :end2 5))
                   (error 'libtmux:unsupported-tmux :message "Executable did not report a tmux release"))
                 (setf (slot-value client 'libtmux::version) (supported-version (subseq version 5))))
               (allocate-daemon-endpoint owner parent)
               (setf (slot-value (slot-value owner 'probe-client) 'libtmux::socket-path)
                     (copy-seq (slot-value owner 'socket))
                     (slot-value owner 'job)
                     (make-process-job
                      :argv (argument-vector (list program "-D" "-f" "/dev/null" "-S" (slot-value owner 'socket)))
                      :input (octet-vector nil) :environment environment :working-directory cwd
                      :token token :cap diagnostics :start start :deadline (capture-budget-deadline budget)))
               (daemon-stage :prepared owner)
               (let ((hook *daemon-stage-hook*)
                     (opener *child-pidfd-opener*) (signaller *child-signaller*))
                 (setf (slot-value owner 'worker)
                       (sb-thread:make-thread
                        (lambda ()
                          (let ((*daemon-stage-hook* hook)
                                (*child-pidfd-opener* opener) (*child-signaller* signaller))
                            (run-daemon-supervisor owner)))
                        :name "owned tmux daemon")))
               (await-daemon-socket owner budget token)
               (daemon-stage :socket-observed owner)
               (verify-daemon-ready owner (slot-value owner 'probe-client) budget token)
               (request-daemon-ready owner budget token)
               (setf returned t)
               owner)
           (error (cause)
             (setf primary cause)
             (call-with-daemon-lock
              owner (lambda () (setf (slot-value owner 'failure)
                                    (or (slot-value owner 'failure) cause))))))
      (call-with-daemon-lock
       owner (lambda ()
               (setf (slot-value owner 'startup-active) nil)
               (condition-broadcast (slot-value owner 'changed))))
      (unless returned
        (handler-case (libtmux:stop-daemon owner)
          (error (condition) (retain-daemon-cleanup-failure owner condition)))))
    (when primary
      (error 'libtmux:daemon-start-failed :daemon owner :cause primary
             :message "Managed daemon startup failed; inspect ERROR-CAUSE and ERROR-DAEMON"))
    owner))

(defun remove-daemon-endpoint (owner)
  (when (slot-value owner 'directory)
    (unless (equal (slot-value owner 'directory-identity)
                   (daemon-file-identity (slot-value owner 'directory) :directory))
      (error 'libtmux:cleanup-failed :message "Private daemon directory identity changed"))
    (let ((current (and (slot-value owner 'socket)
                        (daemon-file-identity (slot-value owner 'socket) :socket))))
      (when current
        (unless (and (slot-value owner 'socket-identity)
                     (equal current (slot-value owner 'socket-identity)))
          (error 'libtmux:cleanup-failed :message "Daemon socket ownership is unresolved or changed"))
        (sb-posix:unlink (slot-value owner 'socket))))
    (sb-posix:rmdir (slot-value owner 'directory))
    (setf (slot-value owner 'directory) nil)))

(defun join-daemon-supervisor (owner)
  (when (slot-value owner 'worker)
    (multiple-value-bind (result problem)
        (sb-thread:join-thread (slot-value owner 'worker) :timeout 0.75 :default :not-joined)
      (declare (ignore result))
      (case problem
        (:timeout (error 'libtmux:cleanup-failed :message "Daemon supervisor is still active"))
        (:abort
         (let ((condition (make-condition 'libtmux:command-failed
                                         :message "Daemon supervisor aborted; retrying owned cleanup")))
           (call-with-daemon-lock
            owner (lambda () (setf (slot-value owner 'failure)
                                   (or (slot-value owner 'failure) condition))))
           (retain-daemon-cleanup-failure owner condition)))))))

(defun stop-managed-daemon (owner)
  (handler-case
    (let* ((deadline (+ (monotonic-seconds) 0.75))
         (lease
           (call-with-daemon-lock
            owner (lambda ()
                    (when (eq (slot-value owner 'state) :closed) (return-from stop-managed-daemon (values)))
                    (setf (slot-value owner 'stop-requested) t)
                    (when (member (slot-value owner 'state) '(:starting :ready :stopping))
                      (setf (slot-value owner 'state) :stopping)
                      (when (slot-value owner 'job-wake)
                        (when (eq (process-job-token (slot-value owner 'job))
                                  (slot-value owner 'lifetime-token))
                          (libtmux:cancel (slot-value owner 'lifetime-token)))
                        (wake-operation (slot-value owner 'job-wake)))
                      (when (slot-value owner 'startup-active) (wake-daemon-waiters owner)))
                    (loop while (or (slot-value owner 'startup-active) (slot-value owner 'cleanup-owner))
                          for remaining = (- deadline (monotonic-seconds))
                          do (unless (and (plusp remaining)
                                          (condition-wait (slot-value owner 'changed) (slot-value owner 'lock)
                                                          remaining))
                               (return nil))
                          finally (return (setf (slot-value owner 'cleanup-owner) (current-thread))))))))
    (unless lease
      (retain-daemon-owner owner)
      (error 'libtmux:daemon-cleanup-failed :resource owner
             :message "Daemon cleanup owner is still active; retry STOP-DAEMON"))
    (unwind-protect
         (handler-case
             (progn
               (join-daemon-supervisor owner)
               (when (slot-value owner 'job)
                 (unless (cleanup-job (slot-value owner 'job))
                   (error 'libtmux:cleanup-failed :message "Daemon process cleanup remains incomplete")))
               (when (slot-value owner 'probe-client)
                 (libtmux:close-client (slot-value owner 'probe-client)))
               (dolist (slot '(notify event))
                 (when (slot-value owner slot)
                   (close-descriptor (shiftf (slot-value owner slot) nil))))
               (remove-daemon-endpoint owner)
               (call-with-daemon-lock owner (lambda () (setf (slot-value owner 'state) :closed)))
               (forget-daemon-owner owner))
           (error (cause)
             (retain-daemon-cleanup-failure owner cause)
             (error 'libtmux:daemon-cleanup-failed :resource owner :cause cause
                    :message "Owned daemon cleanup failed; retain the owner and retry STOP-DAEMON")))
      (call-with-daemon-lock
       owner (lambda ()
               (setf (slot-value owner 'cleanup-owner) nil)
               (condition-broadcast (slot-value owner 'changed))))))
    (libtmux:daemon-cleanup-failed (condition)
      (retain-daemon-owner owner)
      (error condition))
    (error (cause)
      (retain-daemon-cleanup-failure owner cause)
      (error 'libtmux:daemon-cleanup-failed :resource owner :cause cause
             :message "Daemon stop admission failed; retain the owner and retry STOP-DAEMON")))
  (values))
