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

(defstruct terminal-client
  process pidfd reader wake failure cleanup-failures
  (status-changed (sb-thread:make-semaphore)))

(defvar *terminal-client-pidfd-opener* #'fixture-pidfd-open)

(defun drain-terminal-client (client descriptor)
  (handler-case
      (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8))) (total 0))
        (loop for ready = (libtmux.internal::poll-owned
                           (list (list :terminal descriptor :input)
                                 (list :wake (terminal-client-wake client) :input)
                                 (list :exit (terminal-client-pidfd client) :input)) 1)
              do (when (or (member :wake ready) (member :exit ready)) (return))
                 (when (member :terminal ready)
                   (handler-case
                       (let ((count (sb-sys:with-pinned-objects (buffer)
                                      (sb-posix:read descriptor (sb-sys:vector-sap buffer)
                                                    (length buffer)))))
                         (when (zerop count) (return))
                         (incf total count)
                         (when (> total 1048576)
                           (error "Owned terminal fixture exceeded its byte budget")))
                     (sb-posix:syscall-error (condition)
                       (case (sb-posix:syscall-errno condition)
                         (#.sb-posix:eio (return))
                         ((#.sb-posix:eagain #.sb-posix:eintr) nil)
                         (otherwise (error condition))))))))
    (error (condition) (setf (terminal-client-failure client) condition))))

(defun wait-terminal-status (client statuses)
  (let ((deadline (+ (libtmux.internal::monotonic-seconds) 0.5)))
    (loop
      (when (member (sb-ext:process-status (terminal-client-process client)) statuses)
        (return t))
      (let ((remaining (- deadline (libtmux.internal::monotonic-seconds))))
        (unless (and (plusp remaining)
                     (sb-thread:wait-on-semaphore (terminal-client-status-changed client)
                                                  :timeout remaining))
          (return nil))))))

(defun close-terminal-client (client)
  (let ((process (terminal-client-process client))
        (fd (terminal-client-pidfd client))
        (failures nil) (reader-stopped nil))
    (flet ((attempt (function)
             (handler-case (funcall function)
               (error (condition) (push condition failures)))))
      (attempt
       (lambda ()
         (when process
           (if fd
               (progn
                 (libtmux.internal::pidfd-signal fd sb-posix:sigcont (sb-sys:int-sap 0) 0)
                 (libtmux.internal::pidfd-signal fd sb-posix:sigterm (sb-sys:int-sap 0) 0)
                 (unless (sb-sys:wait-until-fd-usable fd :input 0.5)
                   (libtmux.internal::pidfd-signal fd sb-posix:sigkill (sb-sys:int-sap 0) 0)
                   (unless (sb-sys:wait-until-fd-usable fd :input 0.5)
                     (error "Owned terminal client did not exit"))))
               ;; Before pidfd acquisition there is no reader. Closing our PTY
               ;; makes tmux exit without signaling a possibly reused PID.
               (close (sb-ext:process-pty process)))
           (unless (wait-terminal-status client '(:exited :signaled))
             (error "Owned terminal client was not reaped")))))
      (attempt
       (lambda ()
         (when (terminal-client-reader client)
           (libtmux.internal::wake-operation (terminal-client-wake client))
           (sb-thread:join-thread (terminal-client-reader client) :timeout 0.5))
         (setf reader-stopped t)))
      ;; A failed join retains the descriptors in CLIENT for diagnosis/retry.
      (when reader-stopped
        (attempt (lambda ()
                   (when (terminal-client-wake client)
                     (sb-posix:close (terminal-client-wake client))
                     (setf (terminal-client-wake client) nil))))
        (attempt (lambda ()
                   (when fd
                     (sb-posix:close fd)
                     (setf (terminal-client-pidfd client) nil))))
        (attempt (lambda () (when process (sb-ext:process-close process))))))
    (when (terminal-client-failure client)
      (push (terminal-client-failure client) failures))
    (setf (terminal-client-cleanup-failures client) (nreverse failures))))

(defun call-with-attached-terminal-client (fixture function)
  "Own an ordinary PTY client; never enter the control identification path."
  (let* ((client (make-terminal-client))
         (program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux"))
         (channel (format nil "terminal-ready-~A" (gensym)))
         (finished nil))
    (unwind-protect
         (progn
           (setf (terminal-client-process client)
                 (sb-ext:run-program
                  program (list "-N" "-u" "-S" (fixture-socket fixture)
                                "attach-session" "-t" "=fixture" ";"
                                "wait-for" "-S" channel)
                  :search t :wait nil :pty t :use-posix-spawn nil
                  :input nil :output nil :error nil
                  :status-hook (lambda (process)
                                 (declare (ignore process))
                                 (sb-thread:signal-semaphore (terminal-client-status-changed client)))
                  :environment
                  (cons "TERM=xterm-256color"
                        (remove-if (lambda (entry) (uiop:string-prefix-p "TERM=" entry))
                                   (libtmux.internal::process-environment)))))
           (let* ((process (terminal-client-process client))
                  (pid (sb-ext:process-pid process))
                  (fd (funcall *terminal-client-pidfd-opener* pid 0)))
             (unless (and (>= fd 0) (sb-ext:process-alive-p process))
               (when (>= fd 0) (sb-posix:close fd))
               (error "Terminal fixture exited before ownership was established"))
             (setf (terminal-client-pidfd client) fd)
             (unless (and (= pid (sb-posix:getpgid pid))
                          (= (sb-posix:getsid pid) (sb-posix:getsid 0)))
               (error "Terminal fixture lacks a separate non-orphaned process group")))
           (let ((descriptor (sb-sys:fd-stream-fd
                              (sb-ext:process-pty (terminal-client-process client))))
                 (wake (libtmux.internal::cancellation-event-open)))
             (when (minusp wake) (error "Cannot open terminal fixture wake descriptor"))
             (setf (terminal-client-wake client) wake)
             (libtmux.internal::nonblocking descriptor)
             (setf (terminal-client-reader client)
                   (sb-thread:make-thread (lambda () (drain-terminal-client client descriptor))
                                          :name "owned tmux terminal")))
           (libtmux.internal::check-outcome
            (libtmux.internal::run-process
             (list program "-N" "-S" (fixture-socket fixture) "wait-for" channel)
             :timeout 0.5))
           (multiple-value-prog1 (funcall function client) (setf finished t)))
      (let ((failures (close-terminal-client client)))
        (when (and finished failures) (error (first failures)))))))

(in-suite integration)

(test terminal-fixture-partial-acquisition-retires-the-child
  (with-tmux-fixture (fixture)
    (let* ((observer nil)
          (*terminal-client-pidfd-opener*
            (lambda (pid flags)
              (setf observer (fixture-pidfd-open pid flags))
              -1)))
      (unwind-protect
           (progn
             (signals error
               (call-with-attached-terminal-client fixture
                                                  (lambda (client) (declare (ignore client)))))
             (is (and observer (>= observer 0)))
             (is (sb-sys:wait-until-fd-usable observer :input 0)))
        (when (and observer (>= observer 0)) (sb-posix:close observer))))))

(test terminal-fixture-nonlocal-exit-releases-owned-resources
  (with-tmux-fixture (fixture)
    (let ((owned nil))
      (is (eq :preserved
              (catch 'leave-terminal
                (call-with-attached-terminal-client
                 fixture (lambda (client)
                           (setf owned client)
                           (throw 'leave-terminal :preserved))))))
      (is (null (terminal-client-cleanup-failures owned)))
      (is (not (sb-thread:thread-alive-p (terminal-client-reader owned))))
      (is (null (terminal-client-pidfd owned)))
      (is (null (terminal-client-wake owned)))
      (is (member (sb-ext:process-status (terminal-client-process owned)) '(:exited :signaled)))
      (is (zerop (nth-value 2 (fixture-command fixture "has-session")))))))

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
