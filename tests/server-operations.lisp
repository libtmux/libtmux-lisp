(in-package #:libtmux.tests)

(in-suite integration)

(defclass wait-readiness-transport (libtmux.internal::subprocess-transport)
  ((channel :initarg :channel)))

(defmethod libtmux.internal::execute-command :around
    ((transport wait-readiness-transport) argv &key input timeout output-limit cancel-token keep-input-open)
  (let ((guard (position "if-shell" argv :test #'equal)))
    (if guard
        (let ((prepared (copy-list argv)))
          ;; The same server queue reaches WAIT before servicing readiness.
          (setf (nth (+ guard 3) prepared)
                (concatenate 'string
                             (libtmux.internal::tmux-command-text
                              (list "wait-for" "-S" (slot-value transport 'channel)))
                             " ; " (nth (+ guard 3) prepared)))
          (call-next-method transport prepared :input input :timeout timeout
                                              :output-limit output-limit :cancel-token cancel-token
                                              :keep-input-open keep-input-open))
        (call-next-method))))

(defun exercise-queued-channel-request (client fixture channel operation &optional action)
  (let* ((nonce (format nil "~36R" (random (ash 1 128))))
         (ready (concatenate 'string "queued-" nonce))
         (program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux"))
         (token (libtmux:make-cancellation-token))
         (original (slot-value client 'libtmux::transport))
         (worker nil) (failure nil) (result nil))
    (unwind-protect
         (progn
           (setf (slot-value client 'libtmux::transport)
                 (make-instance 'wait-readiness-transport :channel ready)
                 worker
                 (sb-thread:make-thread
                  (lambda ()
                    (handler-case
                        (setf result (libtmux:wait-for client channel :operation operation
                                                      :cancel-token token))
                      (error (condition) (setf failure condition))))))
           (unless (eq :succeeded
                       (libtmux:outcome-status
                        (libtmux.internal::run-process
                         (list program "-N" "-S" (fixture-socket fixture) "wait-for" ready)
                         :timeout 0.5)))
             (error "Owned wait request did not report readiness"))
           (is (= 1 (count #\Newline (fixture-ok fixture "wait-for" "-l" channel))))
           (if action (funcall action) (libtmux:cancel token))
           (sb-thread:join-thread worker :timeout 0.75)
           (if action
               (progn (is (null failure))
                      (is (eq :succeeded (libtmux:outcome-status result))))
               (progn (is (typep failure 'libtmux:command-cancelled))
                      (is (eq :unknown (libtmux:outcome-status (libtmux:error-outcome failure))))))
           ;; Observe disposal directly; CLI join is not a daemon EOF barrier.
           (is (equal "" (fixture-ok fixture "wait-for" "-l" channel))))
      (libtmux:cancel token)
      (when worker (sb-thread:join-thread worker :timeout 0.75))
      (setf (slot-value client 'libtmux::transport) original))))

(test wait-channel-literals-and-version-gates
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((channel (format nil "-literal-#{pid};λ'\"~%channel"))
            (program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")))
        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:wait-for client channel :operation :signal))))
        (is (eq :succeeded
                (libtmux:outcome-status
                 (libtmux.internal::run-process
                  (list program "-N" "-S" (fixture-socket fixture) "wait-for" "--" channel)
                  :timeout 0.5))))
        (unless (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8")
          (dolist (operation '(:wait :lock))
            (handler-case
                (progn (libtmux:wait-for client channel :operation operation)
                       (fail "An older daemon admitted a blocking channel request"))
              (libtmux:unsupported-capability (condition)
                (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))
                (is (equal "3.8" (libtmux:error-required-version condition)))))))
        (signals libtmux:command-failed
          (libtmux:wait-for client "not-locked" :operation :unlock))))))

(test wait-channel-cancellation-removes-queued-waiters-without-unlocking
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (when (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8")
        (libtmux:wait-for client "ready" :operation :signal)
        (is (eq :succeeded (libtmux:outcome-status (libtmux:wait-for client "ready"))))
        ;; Two signals remove the pending wake. The following wait must queue.
        (libtmux:wait-for client "ready" :operation :signal)
        (libtmux:wait-for client "ready" :operation :signal)
        (exercise-queued-channel-request client fixture "ready" :wait)
        (with-fixture-client (signaller fixture)
          (exercise-queued-channel-request
           client fixture "ready" :wait
           (lambda () (libtmux:wait-for signaller "ready" :operation :signal))))
        ;; A lost reply and closing the initiating client do not release a lock.
        (with-fixture-client (holder fixture)
          (setf (slot-value holder 'libtmux::transport)
                (make-instance 'receipt-loss-transport :keep-entry t))
          (signals libtmux:outcome-unknown
            (libtmux:wait-for holder "lock" :operation :lock)))
        (exercise-queued-channel-request client fixture "lock" :lock)
        (with-fixture-client (signaller fixture)
          (exercise-queued-channel-request
           client fixture "lock" :lock
           (lambda () (libtmux:wait-for signaller "lock" :operation :unlock))))
        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:wait-for client "lock" :operation :unlock))))
        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:wait-for client "lock" :operation :lock))))
        (libtmux:wait-for client "lock" :operation :unlock)))))
