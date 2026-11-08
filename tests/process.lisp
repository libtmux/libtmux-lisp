(in-package #:libtmux.tests)

(in-suite integration)

(defun process-arguments (mode &rest extra)
  (append (list "/usr/bin/python3" "-u"
                (namestring (asdf:system-relative-pathname "libtmux" "tests/process-child.py"))
                mode)
          extra))

(defun process-case (mode &rest options)
  (let (process)
    (let* ((libtmux.internal::*process-started-hook*
             (lambda (owned) (setf process owned)))
           (outcome (apply #'libtmux.internal::run-process
                           (process-arguments mode) (append options '(:timeout 1)))))
      (when process
        (is (not (uiop:process-alive-p process)))
        (dolist (stream (list (uiop:process-info-input process)
                              (uiop:process-info-output process)
                              (uiop:process-info-error-output process)))
          (is (not (open-stream-p stream)))))
      outcome)))

(test child-process-context-is-owned-and-local
  "Explicit bootstrap inputs must not replace ordinary command defaults or parent state."
  (let* ((directory (sb-posix:mkdtemp "/tmp/libtmux-lisp-context-XXXXXX"))
         (child-directory (concatenate 'string directory "/literal*[x]\\λ"))
         (selected-directory (copy-seq child-directory))
         (environment (mapcar #'copy-seq '("LC_ALL=C" "SHLVL=47" "LIBTMUX_CONTEXT=owned")))
         (parent-directory (sb-posix:getcwd))
         (parent-environment (sb-ext:posix-environ))
         (selected-job nil))
    (unwind-protect
         (progn
           (sb-posix:mkdir child-directory #o700)
           (let* ((libtmux.internal::*process-launched-hook*
                    (lambda (job)
                      (setf selected-job job)
                      (setf (char (third environment) 16) #\X
                            (char selected-directory (1- (length selected-directory))) #\X)))
                  (outcome (libtmux.internal::run-process
                            (process-arguments "context" "LC_ALL" "SHLVL" "LIBTMUX_CONTEXT")
                            :environment environment :working-directory selected-directory :timeout 1)))
             (is (eq :succeeded (libtmux:outcome-status outcome)))
             (is (equal (list "C" "47" "owned" child-directory)
                        (uiop:split-string (libtmux.internal::strict-text (libtmux:outcome-stdout outcome))
                                           :separator '(#\Null)))))
           (is (equal '("LC_ALL=C" "SHLVL=47" "LIBTMUX_CONTEXT=owned")
                      (libtmux.internal::process-job-environment selected-job)))
           (is (string= child-directory (libtmux.internal::process-job-working-directory selected-job)))
           (dolist (options '(nil (:environment nil)))
             (let ((outcome (apply #'libtmux.internal::run-process
                                   (process-arguments "context" "LC_ALL" "SHLVL")
                                   :timeout 1 options)))
               (is (eq :succeeded (libtmux:outcome-status outcome)))
               (is (equal (list (if options "<absent>" "C.UTF-8") "0" parent-directory)
                          (uiop:split-string (libtmux.internal::strict-text (libtmux:outcome-stdout outcome))
                                             :separator '(#\Null))))))
           (is (string= parent-directory (sb-posix:getcwd)))
           (is (equal parent-environment (sb-ext:posix-environ)))
           (is (not (uiop:process-alive-p (libtmux.internal::process-job-process selected-job))))
           (is (null (libtmux.internal::process-job-pidfd selected-job))))
      (sb-posix:rmdir child-directory)
      (sb-posix:rmdir directory))))

(test concurrent-pipes-and-partial-input
  "The child fills both output pipes before reading a megabyte of stdin."
  (let ((input (make-array 1048576 :element-type '(unsigned-byte 8))))
    (dotimes (i (length input)) (setf (aref input i) (mod i 256)))
    (let* ((outcome (process-case "duplex-input" :input input :timeout 1))
           (output (libtmux:outcome-stdout outcome))
           (error-output (libtmux:outcome-stderr outcome)))
      (is (eq :succeeded (libtmux:outcome-status outcome)))
      (is (= 1179648 (length output)))
      (is (= 131072 (length error-output)))
      (is (equalp input (subseq output 131072)))
      (is (loop for i below 131072
                always (= (- 255 (mod i 256)) (aref error-output i)))))))

(test held-input-retires-on-natural-exit-or-stop
  "A one-shot native control command must not receive early EOF."
  (let ((outcome (process-case "held-input" :keep-input-open t)))
    (is (eq :succeeded (libtmux:outcome-status outcome)))
    (is (string= "held:" (libtmux.internal::strict-text (libtmux:outcome-stdout outcome)))))
  (let ((outcome (libtmux.internal::run-process
                  (process-arguments "held-input" "5") :keep-input-open t
                  :input (libtmux.internal::encode-utf8 "hello") :timeout 1)))
    (is (eq :succeeded (libtmux:outcome-status outcome)))
    (is (string= "held:hello" (libtmux.internal::strict-text (libtmux:outcome-stdout outcome)))))
  (let ((outcome (process-case "wait" :keep-input-open t :timeout 0.1)))
    (is (eq :deadline (libtmux:outcome-reason outcome)))
    (is (eq :unknown (libtmux:outcome-status outcome)))))

(test raw-bytes-argv-and-owned-outcomes
  (let* ((outcome (process-case "bytes"))
         (bytes (libtmux:outcome-stdout outcome)))
    (is (= 256 (length bytes)))
    (is (loop for byte across bytes for i from 0 always (= byte i)))
    (setf (aref bytes 0) 99)
    (is (zerop (aref (libtmux:outcome-stdout outcome) 0)))
    (signals libtmux:decoding-error (libtmux.internal::strict-text bytes)))
  (let* ((arguments (list "" "space here" "x;${};`raw`" "λ" "back\\slash"
                          (format nil "line~%break")))
         (expected (with-output-to-string (stream)
                     (loop for value in arguments for first = t then nil
                           do (unless first (write-char #\Null stream))
                              (write-string value stream))))
         (outcome (libtmux.internal::run-process
                   (apply #'process-arguments "argv" arguments) :timeout 1)))
    (is (equalp (libtmux.internal::encode-utf8 expected)
                (libtmux:outcome-stdout outcome)))))

(test bounded-output-failure-and-deadline
  (let ((result (process-case "failed")))
    (is (eq :failed (libtmux:outcome-status result)))
    (is (= 7 (libtmux:outcome-exit-code result)))
    (is (equal "partial" (libtmux.internal::strict-text (libtmux:outcome-stdout result))))
    (signals libtmux:command-failed (libtmux.internal::check-outcome result)))
  (let ((result (process-case "limit" :output-limit 4096)))
    (is (eq :output-limit (libtmux:outcome-reason result)))
    (is (= 4096 (+ (length (libtmux:outcome-stdout result))
                   (length (libtmux:outcome-stderr result))))))
  (is (eq :succeeded (libtmux:outcome-status
                     (process-case "exact-limit" :output-limit 4096))))
  (let ((result (process-case "wait" :timeout 0.1)))
    (is (eq :deadline (libtmux:outcome-reason result)))
    (is (eq :unknown (libtmux:outcome-status result))))
  (let ((result (process-case "epipe"
                             :input (make-array 1048576 :element-type '(unsigned-byte 8)
                                                        :initial-element 1))))
    (is (eq :stdin-closed (libtmux:outcome-reason result))))
  (let ((result (process-case "inherited-pipes")))
    (is (eq :post-exit-drain (libtmux:outcome-reason result)))
    (is (= 0 (libtmux:outcome-exit-code result)))))

(test cancellation-before-dispatch
  (let ((token (libtmux:make-cancellation-token)) (started nil))
    (libtmux:cancel token)
    (let* ((libtmux.internal::*process-started-hook*
             (lambda (process) (declare (ignore process)) (setf started t)))
           (outcome (libtmux.internal::run-process (process-arguments "wait")
                                                  :cancel-token token)))
      (is (not started))
      (is (eq :not-dispatched (libtmux:outcome-status outcome)))
      (is (eq :cancelled (libtmux:outcome-reason outcome)))
      (is (null (slot-value token 'libtmux::registrations))))))

(test partial-launch-keeps-cleanup-ownership
  "A failed pidfd acquisition must retain the gated child for a later close."
  (let ((client (make-instance 'libtmux:client)) (job nil) (directory nil))
    (unwind-protect
         (progn
           (let ((libtmux.internal::*child-pidfd-opener*
                   (lambda (pid flags) (declare (ignore pid flags)) -1))
                 (libtmux.internal::*process-launched-hook*
                   (lambda (owned)
                     (setf job owned directory (libtmux.internal::process-job-directory owned)))))
             (signals libtmux:command-failed
               (libtmux.internal::call-with-operation
                client nil
                (lambda (token)
                  (libtmux.internal::run-process (process-arguments "wait")
                                                 :cancel-token token :timeout 0.2)))))
           (is (not (libtmux:client-open-p client)))
           (libtmux:close-client client)
           (is (not (uiop:process-alive-p (libtmux.internal::process-job-process job))))
           (is (not (probe-file directory))))
      ;; Failure of the regression itself must not strand its child.
      (when (and job (uiop:process-alive-p (libtmux.internal::process-job-process job)))
        (let ((fd (libtmux.internal::pidfd-open
                   (uiop:process-info-pid (libtmux.internal::process-job-process job)) 0)))
          (when (>= fd 0)
            (unwind-protect
                 (progn
                   (libtmux.internal::pidfd-signal fd sb-posix:sigkill (sb-sys:int-sap 0) 4)
                   (sb-sys:wait-until-fd-usable fd :input 0.5)
                   (uiop:wait-process (libtmux.internal::process-job-process job)))
              (sb-posix:close fd)))))
      (when job (libtmux.internal::cleanup-job job)))))

(test launch-attribution-and-closed-pipe-descendant
  (dolist (code '(126 127))
    (let ((result (libtmux.internal::run-process (process-arguments "exit" (princ-to-string code))
                                                :timeout 1)))
      (is (eq :failed (libtmux:outcome-status result)))
      (is (= code (libtmux:outcome-exit-code result)))))
  (is (eq :succeeded (libtmux:outcome-status (process-case "closed-pipes"))))
  (let ((token (libtmux:make-cancellation-token)) (job nil) (directory nil))
    (let* ((libtmux.internal::*process-launched-hook*
             (lambda (owned)
               (setf job owned directory (libtmux.internal::process-job-directory owned))
               (libtmux:cancel token)))
           (result (libtmux.internal::run-process (process-arguments "wait")
                                                 :cancel-token token :timeout 1)))
      (is (eq :not-dispatched (libtmux:outcome-status result)))
      (is (eq :cancelled (libtmux:outcome-reason result)))
      (is (not (probe-file directory)))
      (is (not (uiop:process-alive-p (libtmux.internal::process-job-process job)))))))

(test executable-failure-and-private-poll
  "Exec rejection differs from a real target exit; unrelated REPL handlers stay idle."
  (let* ((directory (sb-posix:mkdtemp "/tmp/libtmux-lisp-exec-XXXXXX"))
         (program (concatenate 'string directory "/target")))
    (unwind-protect
         (progn
           (dolist (failure '(:missing :permission))
             (uiop:copy-file "/usr/bin/true" program)
             (sb-posix:chmod program #o700)
             (let* ((libtmux.internal::*process-launched-hook*
                      (lambda (job)
                        (declare (ignore job))
                        (ecase failure
                          (:missing (delete-file program))
                          (:permission (sb-posix:chmod program #o600)))))
                    (result (libtmux.internal::run-process (list program) :timeout 1)))
               (is (eq :not-dispatched (libtmux:outcome-status result)))
               (is (eq :exec-failed (libtmux:outcome-reason result)))
               (is (= (ecase failure (:missing 127) (:permission 126))
                      (libtmux:outcome-exit-code result)))))
           (with-open-file (stream program :direction :output :if-exists :supersede)
             (write-line "#!/bin/sh" stream)
             (write-line "exit 0" stream))
           (sb-posix:chmod program #o700)
           (signals libtmux:invalid-argument (libtmux.internal::run-process (list program))))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname directory) :validate t)))
  (let ((fd (libtmux.internal::eventfd-open 0 (logior #o2000000 sb-posix:o-nonblock)))
        (handler nil) (called nil))
    (unwind-protect
         (progn
           (setf handler (sb-sys:add-fd-handler fd :input
                          (lambda (descriptor) (declare (ignore descriptor)) (setf called t))))
           (libtmux.internal::wake-operation fd)
           (is (eq :deadline (libtmux:outcome-reason (process-case "wait" :timeout 0.01))))
           (is (not called)))
      (when handler (sb-sys:remove-fd-handler handler))
      (sb-posix:close fd))))

(test final-kill-failure-and-open-failure-retain-owner
  (let ((client (make-instance 'libtmux:client)) (job nil) (safety-fd nil))
    (unwind-protect
         (progn
           (let ((libtmux.internal::*child-signaller*
                   (lambda (&rest arguments)
                     (if (= (second arguments) sb-posix:sigkill)
                         (error 'libtmux:cleanup-failed :message "Injected signal failure")
                         (apply #'libtmux.internal::pidfd-signal arguments))))
                 (libtmux.internal::*process-launched-hook*
                   (lambda (owned) (setf job owned)))
                 (libtmux.internal::*process-started-hook*
                   (lambda (process)
                     (declare (ignore process))
                     (setf safety-fd (sb-posix:dup (libtmux.internal::process-job-pidfd job)))
                     (sb-posix:fcntl safety-fd sb-posix:f-setfd 1))))
             (signals libtmux:command-failed
               (libtmux.internal::call-with-operation
                client nil
                (lambda (token)
                  (libtmux.internal::run-process (process-arguments "closed-pipes")
                                                 :cancel-token token :timeout 1)))))
           (is (not (libtmux:client-open-p client)))
           (is (= 1 (length (slot-value client 'libtmux::cleanup-jobs))))
           (is (integerp (libtmux.internal::process-job-pidfd job)))
           (libtmux:close-client client)
           (is (null (slot-value client 'libtmux::cleanup-jobs))))
      (when safety-fd
        (libtmux.internal::pidfd-signal safety-fd sb-posix:sigkill (sb-sys:int-sap 0) 4)
        (sb-posix:close safety-fd))
      (libtmux:close-client client)))
  (let ((condition nil) (job nil))
    (unwind-protect
         (progn
           (let ((libtmux.internal::*child-pidfd-opener*
                   (lambda (&rest arguments) (declare (ignore arguments)) -1))
                 (libtmux.internal::*process-launched-hook* (lambda (owned) (setf job owned))))
             (handler-case (libtmux:open-client :program "/usr/bin/true" :timeout 0.1)
               (libtmux:command-failed (failure) (setf condition failure))))
           (is (typep condition 'libtmux:command-failed))
           (is (typep (libtmux:error-client condition) 'libtmux:client))
           (is (not (libtmux:client-open-p (libtmux:error-client condition))))
           (libtmux:close-client (libtmux:error-client condition))
           (is (not (uiop:process-alive-p (libtmux.internal::process-job-process job)))))
      (when job (libtmux.internal::cleanup-job job)))))

(test cancel-and-deadline-at-dispatch-boundary
  (dolist (reason '(:cancelled :deadline))
    (let ((token (libtmux:make-cancellation-token)))
      (let* ((libtmux.internal::*before-dispatch-hook*
               (lambda (job)
                 (ecase reason
                   (:cancelled (libtmux:cancel token))
                   (:deadline (setf (libtmux.internal::process-job-deadline job) 0)))))
             (outcome (libtmux.internal::run-process (process-arguments "wait")
                                                    :cancel-token token :timeout 1)))
        (is (eq :not-dispatched (libtmux:outcome-status outcome)))
        (is (eq reason (libtmux:outcome-reason outcome)))))))

(test cancellation-after-readiness-and-hard-kill
  (let* ((directory (sb-posix:mkdtemp "/tmp/libtmux-lisp-cancel-XXXXXX"))
         (fifo (concatenate 'string directory "/ready"))
         (token (libtmux:make-cancellation-token))
         (reader nil) (worker nil) (result nil) (failure nil))
    (unwind-protect
         (progn
           (sb-posix:mkfifo fifo #o600)
           (setf reader (sb-posix:open fifo (logior sb-posix:o-rdwr sb-posix:o-nonblock)))
           (setf worker
                 (sb-thread:make-thread
                  (lambda ()
                    (handler-case
                        (setf result (libtmux.internal::run-process
                                      (process-arguments "ignore-term" fifo)
                                      :cancel-token token :timeout 1))
                      (error (condition) (setf failure condition))))))
           (is (sb-sys:wait-until-fd-usable reader :input 0.75))
           (libtmux:cancel token)
           (sb-thread:join-thread worker :timeout 0.75)
           (is (null failure))
           (is (eq :cancelled (libtmux:outcome-reason result)))
           (is (= 137 (libtmux:outcome-exit-code result)))
           (is (null (slot-value token 'libtmux::registrations))))
      (libtmux:cancel token)
      (when worker (sb-thread:join-thread worker :timeout 0.75))
      (when reader (sb-posix:close reader))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname directory) :validate t))))

(test close-cancels-active-client-without-killing-daemon
  (with-tmux-fixture (fixture)
    (let ((client (libtmux:open-client :socket-path (fixture-socket fixture)
                                     :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                     :timeout 1))
          (started (sb-thread:make-semaphore)) (worker nil) (condition nil))
      (unwind-protect
           (progn
             (setf worker
                   (sb-thread:make-thread
                    (lambda ()
                      (let ((libtmux.internal::*process-started-hook*
                              (lambda (process)
                                (declare (ignore process))
                                (sb-thread:signal-semaphore started))))
                        (handler-case
                            (libtmux:run-command client '("wait-for" "owned-test-wait")
                                                 :effect :read :timeout 1)
                          (error (value) (setf condition value)))))))
             (is (sb-thread:wait-on-semaphore started :timeout 0.75))
             (signals libtmux:client-busy
               (libtmux:run-command client '("has-session") :effect :read))
             (libtmux:close-client client)
             (sb-thread:join-thread worker :timeout 0.75)
             (is (typep condition 'libtmux:command-cancelled))
             (is (not (libtmux:client-open-p client)))
             (signals libtmux:client-closed
               (libtmux:run-command client '("has-session") :effect :read))
             (is (zerop (nth-value 2 (fixture-command fixture "has-session")))))
        (libtmux:close-client client)
        (when worker (sb-thread:join-thread worker :timeout 0.75))))))
