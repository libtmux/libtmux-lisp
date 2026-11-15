;;; Run a command in its own process group and fail when it leaves descendants.
;;;
;;;   sbcl --script scripts/test-processes/test-processes.lisp COMMAND [ARGUMENT...]
;;;
;;; This process becomes a subreaper, so processes orphaned by the command
;;; reparent to it. When the command exits (or after 60 seconds, when it is
;;; killed), every surviving descendant is killed and counted. The exit status
;;; is the command's, or 1 when a descendant survived. The library never uses
;;; this supervisor; it only checks that tests and examples clean up.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))

(defpackage #:libtmux.scripts.test-processes
  (:use #:cl #:libtmux.scripts)
  (:export #:supervise))

(in-package #:libtmux.scripts.test-processes)

(sb-alien:define-alien-routine ("prctl" %prctl) sb-alien:int
  (option sb-alien:int) (argument sb-alien:unsigned-long) (second sb-alien:unsigned-long)
  (third sb-alien:unsigned-long) (fourth sb-alien:unsigned-long))

(sb-alien:define-alien-routine ("pidfd_send_signal" %pidfd-send-signal) sb-alien:int
  (descriptor sb-alien:int) (signal sb-alien:int) (information sb-sys:system-area-pointer)
  (flags sb-alien:unsigned-int))

(defconstant +set-child-subreaper+ 36)
(defconstant +deadline-seconds+ 60)

(defun child-pids ()
  "Return the pids of this process's direct children, from /proc."
  (let ((text (read-text (format nil "/proc/self/task/~D/children" (sb-posix:getpid)))))
    (mapcar #'parse-integer
            (remove "" (uiop:split-string text :separator '(#\Space #\Newline))
                    :test #'string=))))

(defun reap-or-kill-orphans ()
  "Reap exited children and kill the live ones; return the pids that were alive."
  (let ((leaked '()))
    (loop
      (let ((reaped (handler-case (sb-posix:waitpid -1 sb-posix:wnohang)
                      (sb-posix:syscall-error (condition)
                        (if (= sb-posix:echild (sb-posix:syscall-errno condition))
                            (return)
                            (error condition))))))
        (when (zerop reaped)
          (dolist (child (child-pids))
            (let ((descriptor (pidfd-open child 0)))
              (when (>= descriptor 0)
                (unwind-protect
                     (progn
                       (unless (descriptor-readable-p descriptor 0)
                         (push child leaked)
                         (%pidfd-send-signal descriptor sb-posix:sigkill (sb-sys:int-sap 0) 0))
                       (unless (descriptor-readable-p descriptor 0.5)
                         (fail "Owned test descendant ~D did not terminate" child)))
                  (sb-posix:close descriptor))
                (ignore-errors (sb-posix:waitpid child 0))))))))
    (nreverse leaked)))

(defun exit-status (process)
  (let ((code (sb-ext:process-exit-code process)))
    (if (eq :signaled (sb-ext:process-status process)) (+ 128 code) code)))

(defun supervise (command &key (deadline +deadline-seconds+))
  "Run COMMAND, then kill and count its leftover descendants; return an exit code."
  (unless (zerop (%prctl +set-child-subreaper+ 1 0 0 0))
    (fail "Cannot enable the test-only subreaper"))
  (let* ((process (sb-ext:run-program (first command) (rest command) :search t :wait nil
                                      :input nil :output t :error t))
         (result 1))
    (unwind-protect
         (if (process-exited-p process deadline)
             (progn (sb-ext:process-wait process)
                    (setf result (exit-status process)))
             (format *error-output* "~&FAIL: ~{~A~^ ~} did not exit in ~D seconds~%"
                     command deadline))
      (when (sb-ext:process-alive-p process)
        (sb-posix:kill (- (sb-ext:process-pid process)) sb-posix:sigkill)
        (sb-ext:process-wait process))
      (let ((leaked (reap-or-kill-orphans)))
        (cond (leaked
               (format *error-output* "~&FAIL: ~D owned descendants survived the test image~%"
                       (length leaked))
               (setf result 1))
              ((plusp result)
               ;; A negative test must tell its child's failure from a supervisor failure.
               (format *error-output* "~&Owned child exited ~D; descendant cleanup: PASS~%"
                       result)))))
    result))

(defun main ()
  (let ((command (rest sb-ext:*posix-argv*)))
    (unless command
      (fail "Usage: test-processes.lisp COMMAND [ARGUMENT...]"))
    (supervise command)))

(main-when-script #'main)
