(in-package #:libtmux.internal)

(defvar *child-pidfd-opener* #'pidfd-open)
(defvar *child-signaller* #'pidfd-signal)

(defparameter +exec-barrier+
  (concatenate
   'string
   "shopt -s execfail; exec {gate}<\"$1\"; exec {status}>\"$2\"; shift 2; "
   "printf 'ready\\n' >&\"$status\"; "
   "if ! IFS= read -r -n 1 -u \"$gate\" token || [[ $token != x ]]; then "
   "printf 'gate-failed\\n' >&\"$status\"; exit 125; fi; "
   "exec {gate}<&-; exec -- \"$@\" {status}>&-; result=$?; "
   "printf 'exec-failed:%s\\n' \"$result\" >&\"$status\"; exit \"$result\""))

(defun byte-buffer ()
  (make-array 4096 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))

(defun append-bytes (buffer source count)
  (let* ((start (length buffer)) (needed (+ start count)))
    (when (> needed (array-total-size buffer))
      (adjust-array buffer (max needed (* 2 (array-total-size buffer)))))
    (setf (fill-pointer buffer) needed)
    (replace buffer source :start1 start :end2 count)))

(defstruct process-job
  argv input keep-input-open environment working-directory token cap start deadline
  process pidfd authority wake registered
  directory gate-path status-path gate status dummy
  input-stream input-fd (offset 0)
  (outputs (make-array 2 :initial-element nil))
  (output-fds (make-array 2 :initial-element nil))
  (buffers (vector (byte-buffer) (byte-buffer)))
  (control (byte-buffer)) (scratch (make-array 65536 :element-type '(unsigned-byte 8)))
  (total 0) ready released terminal code reason exec-failed
  kill-at final-at drain-at killed group-cleaned cleanup-failures)

(defun owned-process-environment (environment)
  "Copy a finite sequence of distinct NAME=VALUE strings for one child.
NIL denotes an explicit empty environment. Values may contain equals signs;
names must be nonempty and unique. Limit explicit input to 4096 entries, 64 KiB
UTF-8 per entry and 1 MiB combined. These are preparation bounds, not an exec
size guarantee. This validates data, not executable trust."
  (let ((result nil) (count 0) (bytes 0) (names (make-hash-table :test #'equal)))
    (flet ((accept (entry)
             (when (> (incf count) 4096)
               (invalid-argument "Explicit environment exceeds 4096 entries"))
             (unless (and (stringp entry) (<= (length entry) 65536)
                          (not (find #\Null entry)))
               (invalid-argument "Environment entries must be bounded strings without NUL"))
             (let ((size (length (encode-utf8 entry))) (separator (position #\= entry)))
               (when (or (> size 65536) (> (incf bytes size) 1048576))
                 (invalid-argument "Explicit environment exceeds its UTF-8 byte bounds"))
               (unless (and separator (plusp separator))
                 (invalid-argument "Environment entries must have a nonempty name followed by ="))
               (let ((name (subseq entry 0 separator)))
                 (when (gethash name names)
                   (invalid-argument "Environment names must be unique"))
                 (setf (gethash name names) t)))
             (push (copy-seq entry) result)))
      (cond ((and (vectorp environment) (not (stringp environment)))
             (when (> (length environment) 4096)
               (invalid-argument "Explicit environment exceeds 4096 entries"))
             (map nil #'accept environment))
            ((listp environment)
             (loop for tail = environment then (cdr tail)
                   while tail
                   do (unless (consp tail)
                        (invalid-argument "Environment must be a finite proper list or vector"))
                      (accept (car tail))))
            (t (invalid-argument "Environment must be a finite proper list or vector"))))
    (nreverse result)))

(defun owned-working-directory (directory)
  "Resolve an explicit native directory string; NIL keeps inherited cwd behavior."
  (when directory
    (unless (and (stringp directory) (plusp (length directory))
                 (not (find #\Null directory)))
      (invalid-argument "Working directory must be a nonempty native string without NUL"))
    (let ((path (absolute-native-path directory)))
      (unless (ignore-errors (sb-posix:s-isdir (sb-posix:stat-mode (sb-posix:stat path))))
        (invalid-argument "Working directory must name an existing directory"))
      path)))

(defun raw-write (fd bytes &optional (offset 0))
  (sb-sys:with-pinned-objects (bytes)
    (sb-posix:write fd (sb-sys:sap+ (sb-sys:vector-sap bytes) offset)
                   (- (length bytes) offset))))

(defun signal-job-group (job signal)
  (when (process-job-pidfd job)
    (unless (zerop (funcall *child-signaller* (process-job-pidfd job) signal (sb-sys:int-sap 0)
                           (if (process-job-authority job) 4 0)))
      (unless (= (sb-alien:get-errno) sb-posix:esrch)
        (error 'libtmux:cleanup-failed :message "Cannot signal the owned process group")))
    t))

(defun close-job-input (job)
  (setf (process-job-input-fd job) nil)
  (when (and (process-job-input-stream job)
             (open-stream-p (process-job-input-stream job)))
    (close (process-job-input-stream job) :abort t)))

(defun stop-job (job reason)
  (unless (process-job-final-at job)
    (let ((now (monotonic-seconds)))
      (setf (process-job-reason job) (or (process-job-reason job) reason)
            (process-job-kill-at job) (+ now 0.05)
            (process-job-final-at job) (+ now 0.5)))
    (close-job-input job)
    (when (process-job-gate job) (close-descriptor (shiftf (process-job-gate job) nil)))
    (when (process-job-dummy job) (close-descriptor (shiftf (process-job-dummy job) nil)))
    (signal-job-group job sb-posix:sigterm)))

(defun unlink-if-present (path)
  (handler-case (sb-posix:unlink path)
    (sb-posix:syscall-error (condition)
      (unless (= (sb-posix:syscall-errno condition) sb-posix:enoent)
        (error condition)))))

(defun unlink-job-files (job)
  (when (process-job-gate-path job)
    (unlink-if-present (process-job-gate-path job))
    (setf (process-job-gate-path job) nil))
  (when (process-job-status-path job)
    (unlink-if-present (process-job-status-path job))
    (setf (process-job-status-path job) nil))
  (when (process-job-directory job)
    (sb-posix:rmdir (process-job-directory job))
    (setf (process-job-directory job) nil)))

(defun acquire-job-authority (job)
  (let* ((process (process-job-process job))
         (pid (uiop:process-info-pid process))
         (fd (funcall *child-pidfd-opener* pid 0)))
    (when (>= fd 0) (setf (process-job-pidfd job) fd))
    ;; Recheck the process object after opening: a failed helper may be reaped.
    (unless (uiop:process-alive-p process)
      (when (process-job-pidfd job)
        (close-descriptor (shiftf (process-job-pidfd job) nil))))
    (cond
      ((process-job-pidfd job)
       (unless (= pid (sb-posix:getpgid pid))
         (error 'libtmux:command-failed :message "Launcher did not create an owned process group"))
       (setf (process-job-authority job) t))
      ((not (uiop:process-alive-p process))
       (setf (process-job-terminal job) t
             (process-job-code job) (uiop:wait-process process)
             (process-job-reason job) :launcher-failed))
      (t (error 'libtmux:cleanup-failed :resource job
                :message "Cannot acquire child pidfd; target remains gated")))))

(defun acquire-job (job)
  (setf (process-job-wake job)
        (eventfd-open 0 (logior #o2000000 sb-posix:o-nonblock)))
  (when (minusp (process-job-wake job))
    (setf (process-job-wake job) nil)
    (error 'libtmux:command-failed :message "Cannot allocate cancellation descriptor"))
  (unless (register-token (process-job-token job) (process-job-wake job))
    (setf (process-job-reason job) :cancelled)
    (return-from acquire-job nil))
  (setf (process-job-registered job) t
        (process-job-directory job) (sb-posix:mkdtemp "/tmp/libtmux-lisp-launch-XXXXXX"))
  (sb-posix:chmod (process-job-directory job) #o700)
  (setf (process-job-gate-path job) (concatenate 'string (process-job-directory job) "/gate")
        (process-job-status-path job) (concatenate 'string (process-job-directory job) "/status"))
  (dolist (path (list (process-job-gate-path job) (process-job-status-path job)))
    (sb-posix:mkfifo path #o600)
    (sb-posix:chmod path #o600))
  (setf (process-job-gate job)
        (sb-posix:open (process-job-gate-path job)
                       (logior sb-posix:o-rdwr sb-posix:o-nonblock #o2000000))
        (process-job-status job)
        (sb-posix:open (process-job-status-path job)
                       (logior sb-posix:o-rdonly sb-posix:o-nonblock #o2000000))
        (process-job-dummy job)
        (sb-posix:open (process-job-status-path job)
                       (logior sb-posix:o-wronly sb-posix:o-nonblock #o2000000)))
  (when (or (libtmux:cancelled-p (process-job-token job))
            (>= (monotonic-seconds) (process-job-deadline job)))
    (setf (process-job-reason job)
          (if (libtmux:cancelled-p (process-job-token job)) :cancelled :deadline))
    (return-from acquire-job nil))
  (setf (process-job-process job)
        (uiop:launch-program
         (append (list "/bin/bash" "--noprofile" "--norc" "-p" "-c" +exec-barrier+
                       "libtmux-exec" (process-job-gate-path job) (process-job-status-path job))
                 (coerce (process-job-argv job) 'list))
         :input :stream :output :stream :error-output :stream :force-shell nil
         :environment (process-job-environment job)
         :directory (and (process-job-working-directory job)
                         (sb-ext:parse-native-namestring (process-job-working-directory job)))
         :external-format :utf-8))
  (let ((process (process-job-process job)))
    (setf (process-job-input-stream job) (uiop:process-info-input process)
          (process-job-input-fd job) (sb-sys:fd-stream-fd (uiop:process-info-input process))
          (aref (process-job-outputs job) 0) (uiop:process-info-output process)
          (aref (process-job-outputs job) 1) (uiop:process-info-error-output process))
    (nonblocking (process-job-input-fd job))
    (dotimes (i 2)
      (setf (aref (process-job-output-fds job) i)
            (sb-sys:fd-stream-fd (aref (process-job-outputs job) i)))
      (nonblocking (aref (process-job-output-fds job) i))))
  (when *process-launched-hook* (funcall *process-launched-hook* job))
  (acquire-job-authority job)
  (when (process-job-terminal job)
    (close-descriptor (shiftf (process-job-dummy job) nil)))
  t)

(defun release-job (job)
  (close-descriptor (shiftf (process-job-dummy job) nil))
  (unlink-job-files job)
  (when *before-dispatch-hook* (funcall *before-dispatch-hook* job))
  (let ((stopped
          (call-with-lock
           (slot-value (process-job-token job) 'libtmux::lock)
           (lambda ()
             (handler-case
                 (cond ((slot-value (process-job-token job) 'libtmux::cancelled-p) :cancelled)
                       ((>= (monotonic-seconds) (process-job-deadline job)) :deadline)
                       (t
                        (unless (= 1 (raw-write (process-job-gate job) (octet-vector #(120))))
                          (error 'libtmux:command-failed :message "Cannot release the executable gate"))
                        (setf (process-job-released job) t)
                        nil))
               (error (condition) condition))))))
    (when (typep stopped 'error) (error stopped))
    (when stopped (stop-job job stopped) (return-from release-job nil)))
  (close-descriptor (shiftf (process-job-gate job) nil))
  (when (and (zerop (length (process-job-input job)))
             (not (process-job-keep-input-open job)))
    (close-job-input job))
  (when *process-started-hook* (funcall *process-started-hook* (process-job-process job))))

(defun read-job (job which fd)
  (handler-case
      (let* ((scratch (process-job-scratch job))
             (n (sb-sys:with-pinned-objects (scratch)
                  (sb-posix:read fd (sb-sys:vector-sap scratch) (length scratch)))))
        (cond
          ((zerop n)
           (if (eq which :control)
               (close-descriptor (shiftf (process-job-status job) nil))
               (progn
                 (setf (aref (process-job-output-fds job) which) nil)
                 (close (aref (process-job-outputs job) which) :abort t))))
          ((eq which :control)
           (when (> (+ (length (process-job-control job)) n) 128)
             (error 'libtmux:command-failed :message "Invalid launcher control record"))
           (append-bytes (process-job-control job) scratch n))
          (t
           (let ((retained (min n (- (process-job-cap job) (process-job-total job)))))
             (append-bytes (aref (process-job-buffers job) which) scratch retained)
             (incf (process-job-total job) retained)
             (when (< retained n) (stop-job job :output-limit)))))
        (when (eq which :control)
          (let ((text (decode-utf8 (process-job-control job))))
            (when (and (>= (length text) 6) (string= text (format nil "ready~%") :end1 6))
              (setf (process-job-ready job) t))
            (when (search "exec-failed:" text)
              (setf (process-job-exec-failed job) t
                    (process-job-reason job) :exec-failed)))))
    (sb-posix:syscall-error (condition)
      (unless (member (sb-posix:syscall-errno condition) (list sb-posix:eagain sb-posix:eintr))
        (error condition)))))

(defun write-job-input (job)
  (handler-case
      (incf (process-job-offset job)
            (raw-write (process-job-input-fd job) (process-job-input job)
                       (process-job-offset job)))
    (sb-posix:syscall-error (condition)
      (case (sb-posix:syscall-errno condition)
        (#.sb-posix:epipe (stop-job job :stdin-closed))
        ((#.sb-posix:eagain #.sb-posix:eintr) nil)
        (otherwise (error condition)))))
  (when (and (= (process-job-offset job) (length (process-job-input job)))
             (not (process-job-keep-input-open job)))
    (close-job-input job)))

(defun reap-job (job)
  (unless (process-job-terminal job)
    (setf (process-job-terminal job) t
          (process-job-code job) (uiop:wait-process (process-job-process job))
          (process-job-drain-at job) (+ (monotonic-seconds) 0.05))
    (when (process-job-dummy job) (close-descriptor (shiftf (process-job-dummy job) nil)))
    (when (and (process-job-released job) (process-job-input-fd job)
               (< (process-job-offset job) (length (process-job-input job))))
      (stop-job job :stdin-closed))
    (close-job-input job)))

(defun job-reads-open-p (job)
  (or (process-job-status job) (some #'identity (process-job-output-fds job))))

(defun supervise-job (job &key before-step)
  "Service one owned job. BEFORE-STEP runs on this supervisor, never another reader.
Only an admitted persistent owner may retire the startup deadline to NIL; its
close wake remains registered, and stop/drain/kill bounds remain finite."
  (loop
    do (when before-step (funcall before-step job))
       (let ((now (monotonic-seconds)))
         (unless (process-job-final-at job)
           (cond ((libtmux:cancelled-p (process-job-token job)) (stop-job job :cancelled))
                 ((and (process-job-deadline job) (>= now (process-job-deadline job)))
                  (stop-job job :deadline))
                 ((and (process-job-terminal job) (job-reads-open-p job)
                       (process-job-drain-at job) (>= now (process-job-drain-at job)))
                  (stop-job job :post-exit-drain))))
         (when (and (process-job-ready job) (not (process-job-released job))
                    (not (process-job-reason job)) (not (process-job-terminal job)))
           (release-job job))
         (when (and (process-job-kill-at job) (>= now (process-job-kill-at job))
                    (not (process-job-killed job)))
           (signal-job-group job sb-posix:sigkill)
           (setf (process-job-killed job) t))
         (when (and (process-job-terminal job) (not (job-reads-open-p job))) (return))
         (when (and (process-job-final-at job) (>= now (process-job-final-at job)))
           (error 'libtmux:cleanup-failed :message "Process cleanup exceeded its bound"))
         (let* ((entries
                  (append
                   (loop for fd across (process-job-output-fds job) for i from 0
                         when fd collect (list i fd :input))
                   (when (process-job-status job) (list (list :control (process-job-status job) :input)))
                   (when (and (process-job-input-fd job) (process-job-released job)
                              (< (process-job-offset job) (length (process-job-input job))))
                     (list (list :input (process-job-input-fd job) :output)))
                   (when (and (process-job-pidfd job) (not (process-job-terminal job)))
                     (list (list :child (process-job-pidfd job) :input)))
                   (unless (process-job-reason job)
                     (list (list :cancel (process-job-wake job) :input)))))
                (bounds (remove nil
                                (if (process-job-reason job)
                                    (list (and (not (process-job-killed job)) (process-job-kill-at job))
                                          (or (process-job-final-at job) (process-job-deadline job)))
                                    (list (process-job-deadline job) (process-job-drain-at job)))))
                (wait (and bounds (max 0 (- (apply #'min bounds) (monotonic-seconds))))))
           (dolist (ready (poll-owned entries wait))
             (case ready
               (:input (when (process-job-input-fd job) (write-job-input job)))
               (:child (reap-job job))
               (:cancel
                (consume-wake (process-job-wake job))
                (when (libtmux:cancelled-p (process-job-token job)) (stop-job job :cancelled)))
               (:control (when (process-job-status job) (read-job job :control (process-job-status job))))
               (otherwise
                (when (aref (process-job-output-fds job) ready)
                  (read-job job ready (aref (process-job-output-fds job) ready))))))))))

(defun cleanup-job (job)
  (flet ((attempt (function)
           (handler-case (funcall function)
             (error (condition)
               (setf (process-job-cleanup-failures job)
                     (subseq (cons condition (process-job-cleanup-failures job))
                             0 (min 16 (1+ (length (process-job-cleanup-failures job))))))
               (when *operation-client* (record-cleanup-failure *operation-client* condition))
               nil))))
    ;; Retire wake and ordinary pipes first, freeing slots for a failed pidfd open.
    (when (process-job-wake job)
      (attempt (lambda ()
                 (if (process-job-registered job)
                     (retire-token (process-job-token job) (shiftf (process-job-wake job) nil))
                     (close-descriptor (shiftf (process-job-wake job) nil))))))
    (when (process-job-process job)
      (attempt (lambda () (uiop:close-streams (process-job-process job))))
      (setf (process-job-input-fd job) nil)
      (fill (process-job-output-fds job) nil)
      (when (and (not (process-job-terminal job)) (not (process-job-pidfd job)))
        (attempt (lambda () (acquire-job-authority job))))
      ;; EOF does not establish descendant exit. Kill the retained group on success too.
      (unless (process-job-group-cleaned job)
        (setf (process-job-group-cleaned job)
              (if (process-job-pidfd job)
                  (attempt (lambda () (signal-job-group job sb-posix:sigkill)))
                  (and (process-job-terminal job) (not (process-job-released job))))))
      (attempt
       (lambda ()
         (unless (process-job-terminal job)
           (cond ((not (uiop:process-alive-p (process-job-process job))) (reap-job job))
                 ((and (process-job-pidfd job)
                       (poll-owned (list (list :child (process-job-pidfd job) :input)) 0.5))
                  (reap-job job))
                 (t (error 'libtmux:cleanup-failed
                           :resource job
                           :message "Owned child has not exited; cleanup is incomplete"))))))
      (unless (and (process-job-terminal job) (process-job-group-cleaned job))
        ;; Keep the gate and names: a broker which has not opened them must not strand.
        (when *operation-client* (retain-cleanup-job *operation-client* job))
        (return-from cleanup-job nil)))
    (when (process-job-gate job)
      (attempt (lambda () (close-descriptor (shiftf (process-job-gate job) nil)))))
    (when (process-job-dummy job)
      (attempt (lambda () (close-descriptor (shiftf (process-job-dummy job) nil)))))
    (when (process-job-status job)
      (attempt (lambda () (close-descriptor (shiftf (process-job-status job) nil)))))
    (when (process-job-pidfd job)
      (attempt (lambda () (close-descriptor (shiftf (process-job-pidfd job) nil)))))
    (attempt (lambda () (unlink-job-files job)))
    (if (process-job-directory job)
        (progn (when *operation-client* (retain-cleanup-job *operation-client* job)) nil)
        t)))

(defun process-job-outcome (job &optional primary)
  (let ((outcome
          (make-outcome
           (process-job-argv job)
           (cond ((or (not (process-job-released job)) (process-job-exec-failed job)) :not-dispatched)
                 ((or primary (process-job-reason job) (process-job-cleanup-failures job)) :unknown)
                 ((eql (process-job-code job) 0) :succeeded) (t :failed))
           (cond ((process-job-exec-failed job) :launching)
                 ((process-job-terminal job) :exited)
                 ((process-job-released job) :dispatched)
                 ((process-job-process job) :launching) (t :prepared))
           (process-job-start job) :stdout (copy-seq (aref (process-job-buffers job) 0))
           :stderr (copy-seq (aref (process-job-buffers job) 1))
           :code (process-job-code job) :reason (process-job-reason job))))
    (setf (slot-value outcome 'libtmux::cleanup-failures) (process-job-cleanup-failures job))
    outcome))

(defun run-process (arguments &key input keep-input-open (timeout 30)
                                  (output-limit (* 16 1024 1024)) cancel-token
                                  (environment nil environment-p) working-directory)
  "Execute owned argv with bounded pipes, cancellation and process cleanup.
Private KEEP-INPUT-OPEN lets a one-shot native protocol retire naturally rather
than receiving EOF after input is sent. Exhausted held input is never polled
for writing; actual child exit and all stop/cleanup paths still close it.
ENVIRONMENT and WORKING-DIRECTORY are copied and validated before the supervised
timer starts. Omitted ENVIRONMENT uses ordinary command locale/selector policy;
explicit NIL starts with no inherited entries. The trusted Bash launcher may
normalize shell metadata such as SHLVL. WORKING-DIRECTORY changes only the child
cwd; NIL inherits it. Neither option changes the Lisp process environment/cwd."
  (check-limits timeout output-limit)
  (unless (or (null keep-input-open) (eq keep-input-open t))
    (invalid-argument "keep-input-open must be T or NIL"))
  (let ((argv (argument-vector arguments)) (input (octet-vector input))
        (environment (if environment-p (owned-process-environment environment)
                         (mapcar #'copy-seq (process-environment))))
        (working-directory (owned-working-directory working-directory))
        (token (or cancel-token (libtmux:make-cancellation-token))))
    (check-type token libtmux:cancellation-token)
    (unless (plusp (length argv)) (invalid-argument "An executable is required"))
    (setf (aref argv 0) (native-program (aref argv 0)))
    (let* ((start (monotonic-seconds))
           (job (make-process-job :argv argv :input input :keep-input-open keep-input-open
                                  :environment environment :working-directory working-directory
                                  :token token :cap output-limit
                                  :start start :deadline (+ start timeout)))
           (primary nil))
      (unwind-protect
           (handler-case
               (cond ((libtmux:cancelled-p token) (setf (process-job-reason job) :cancelled))
                     ((zerop timeout) (setf (process-job-reason job) :deadline))
                     (t (ensure-process-platform)
                        (when (acquire-job job) (supervise-job job))))
             (error (condition) (setf primary condition)))
        (cleanup-job job))
      (let ((outcome (process-job-outcome job primary)))
        (when (or primary (process-job-cleanup-failures job))
          (error 'libtmux:command-failed :outcome outcome
                 :cause (or primary (first (process-job-cleanup-failures job)))
                 :message "Process transport failed; inspect the retained cause and outcome"))
        outcome))))
