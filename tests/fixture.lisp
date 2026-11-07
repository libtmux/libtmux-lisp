(in-package #:libtmux.tests)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(sb-alien:define-alien-routine ("pidfd_open" fixture-pidfd-open) sb-alien:int
  (pid sb-alien:int) (flags sb-alien:unsigned-int))

(defstruct fixture directory socket pid pidfd)

(defun fixture-command (fixture &rest arguments)
  (uiop:run-program
   (append (list "env" "-u" "TMUX" "-u" "TMUX_PANE"
                 "LC_ALL=C.UTF-8" "TERM=xterm-256color"
                 (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                 "-u" "-S" (fixture-socket fixture) "-f" "/dev/null")
           arguments)
   :force-shell nil :input nil :output :string :error-output :string
   :ignore-error-status t))

(defun stop-fixture (fixture)
  (unwind-protect
       (progn
         (fixture-command fixture "kill-server")
         (when (fixture-pidfd fixture)
           (unless (sb-sys:wait-until-fd-usable
                    (fixture-pidfd fixture) :input 0.5)
             (error "Owned tmux fixture did not terminate"))))
    (when (fixture-pidfd fixture)
      (sb-posix:close (fixture-pidfd fixture))
      (setf (fixture-pidfd fixture) nil))
    (uiop:delete-directory-tree (fixture-directory fixture) :validate t)))

(defun call-with-fixture (function &key (socket-suffix "socket"))
  (let* ((directory (sb-posix:mkdtemp "/tmp/libtmux-lisp-XXXXXX"))
         (fixture (make-fixture
                   :directory (uiop:ensure-directory-pathname directory)
                   :socket (concatenate 'string directory "/" socket-suffix))))
    (unwind-protect
         (progn
           (multiple-value-bind (output diagnostics code)
               (fixture-command fixture "new-session" "-d" "-s" "fixture"
                                "/bin/cat")
             (declare (ignore output))
             (unless (zerop code)
               (error "Cannot start owned fixture: ~A" diagnostics)))
           (multiple-value-bind (pid-text diagnostics code)
               (fixture-command fixture "display-message" "-p" "#{pid}")
             (unless (zerop code)
               (error "Cannot inspect fixture PID: ~A" diagnostics))
             (setf (fixture-pid fixture)
                   (parse-integer pid-text :junk-allowed t)))
           (let ((fd (fixture-pidfd-open (fixture-pid fixture) 0)))
             (when (minusp fd) (error "Cannot open owned fixture pidfd"))
             (setf (fixture-pidfd fixture) fd))
           (funcall function fixture))
      (stop-fixture fixture))))

(defmacro with-tmux-fixture ((name &rest options) &body body)
  `(call-with-fixture (lambda (,name) ,@body) ,@options))

(defun call-with-attached-control-client (fixture function)
  "Own one tmux control client for attached-client observation tests."
  (let ((process nil) (pidfd nil))
    (unwind-protect
         (progn
           (setf process
                 (uiop:launch-program
                  (list (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                        "-N" "-u" "-S" (fixture-socket fixture) "-C"
                        "attach-session" "-t" "fixture")
                  :input :stream :output :stream :error-output :stream :force-shell nil
                  :environment (libtmux.internal::process-environment)))
           (setf pidfd (fixture-pidfd-open (uiop:process-info-pid process) 0))
           (when (or (minusp pidfd) (not (uiop:process-alive-p process)))
             (when (>= pidfd 0) (sb-posix:close pidfd))
             (setf pidfd nil)
             (error "Control fixture exited before ownership was established"))
           (let ((fd (sb-sys:fd-stream-fd (uiop:process-info-output process)))
                 (bytes (libtmux.internal::byte-buffer))
                 (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
                 (deadline (+ (libtmux.internal::monotonic-seconds) 0.5)))
             (libtmux.internal::nonblocking fd)
             (loop until (search "%session-changed" (libtmux.internal::strict-text bytes))
                   for remaining = (- deadline (libtmux.internal::monotonic-seconds))
                   do (unless (and (plusp remaining)
                                   (libtmux.internal::poll-owned (list (list :read fd :input)) remaining))
                        (error "Control fixture did not report session attachment"))
                      (let ((count (sb-sys:with-pinned-objects (buffer)
                                     (sb-posix:read fd (sb-sys:vector-sap buffer) (length buffer)))))
                        (unless (and (plusp count) (< (+ (length bytes) count) 16384))
                          (error "Invalid bounded control fixture startup"))
                        (libtmux.internal::append-bytes bytes buffer count))))
           (funcall function process))
      (when pidfd
        (libtmux.internal::pidfd-signal pidfd sb-posix:sigterm (sb-sys:int-sap 0) 0)
        (unless (sb-sys:wait-until-fd-usable pidfd :input 0.5)
          (libtmux.internal::pidfd-signal pidfd sb-posix:sigkill (sb-sys:int-sap 0) 0)
          (unless (sb-sys:wait-until-fd-usable pidfd :input 0.5)
            (error "Control fixture did not exit")))
        (uiop:wait-process process)
        (sb-posix:close pidfd))
      (when process (uiop:close-streams process)))))

(in-suite integration)

(test owned-fixture-isolation-and-cleanup
  "Two explicitly addressed daemons survive each other's teardown."
  (let (first-directory second-directory)
    (with-tmux-fixture (first)
      (setf first-directory (fixture-directory first))
      (is (equal "kept"
                 (catch 'leave-fixture
                   (with-tmux-fixture (second)
                     (setf second-directory (fixture-directory second))
                     (is (/= (fixture-pid first) (fixture-pid second)))
                     (is (not (equal (fixture-socket first)
                                     (fixture-socket second))))
                     (throw 'leave-fixture "kept")))))
      (is (not (probe-file second-directory)))
      (is (zerop (nth-value 2 (fixture-command first "has-session")))))
    (is (not (probe-file first-directory)))))
