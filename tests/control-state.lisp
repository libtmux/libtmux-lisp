(in-package #:libtmux.tests)

(in-suite control)

(defun local-control-peer (&rest options)
  (let ((peer (apply #'libtmux.internal::%make-control-peer
         :state :ready
         :job (libtmux.internal::make-process-job
               :input (libtmux.internal::octet-vector #())
               :token (libtmux:make-cancellation-token))
                     options)))
    (libtmux.internal::ensure-control-decoder peer)
    peer))

(test control-startup-causes-distinguish-end-timeout-and-cancellation
  (let* ((peer (local-control-peer))
         (job (libtmux.internal::control-peer-job peer))
         (primary (make-condition 'simple-error :format-control "original worker failure")))
    (setf (libtmux.internal::control-peer-state peer) :closed
          (libtmux.internal::control-peer-finished peer) t
          (libtmux.internal::process-job-terminal job) t)
    (let ((end (libtmux.internal::control-startup-cause peer :ready)))
      (is (typep end 'libtmux:command-failed))
      (is (not (typep end 'libtmux:deadline-exceeded))))
    (is (typep (libtmux.internal::control-startup-cause peer :timeout) 'libtmux:deadline-exceeded))
    (setf (libtmux.internal::process-job-reason job) :cancelled)
    (is (typep (libtmux.internal::control-startup-cause peer :ready) 'libtmux:command-cancelled))
    (setf (libtmux.internal::process-job-reason job) :output-limit)
    (is (typep (libtmux.internal::control-startup-cause peer :ready) 'libtmux:output-limit-exceeded))
    (setf (libtmux.internal::control-peer-failure peer) primary)
    (is (eq primary (libtmux.internal::control-startup-cause peer :timeout)))))

(test control-queued-expiry-does-not-wait-for-an-active-request
  (let* ((peer (local-control-peer))
         (active (libtmux.internal::submit-control-command peer '("wait-for" "fixture") :effect :read))
         (expired (libtmux.internal::submit-control-command peer '("display-message" "-p" "unused")
                                                           :effect :read :timeout 0)))
    (libtmux.internal::control-supervisor-step peer (libtmux.internal::control-peer-job peer))
    (libtmux.internal::control-supervisor-step peer (libtmux.internal::control-peer-job peer))
    (multiple-value-bind (result delivery) (libtmux.internal::await-control-request expired :timeout 0)
      (is (eq :ready delivery))
      (is (eq :timed-out (getf result :status)))
      (is (null (getf result :dispatched-p))))
    (is (eq :writing (libtmux.internal::control-request-state active)))))

(test control-poll-deadline-includes-the-earliest-queued-request
  (let* ((peer (local-control-peer))
         (active (libtmux.internal::submit-control-command peer '("wait-for" "fixture") :effect :read :timeout 30))
         (queued (libtmux.internal::submit-control-command peer '("display-message" "-p" "later")
                                                          :effect :read :timeout 1)))
    (libtmux.internal::control-supervisor-step peer (libtmux.internal::control-peer-job peer))
    (is (= (libtmux.internal::control-request-deadline queued)
           (libtmux.internal::process-job-poll-deadline (libtmux.internal::control-peer-job peer))))
    (is (= (libtmux.internal::control-request-deadline active)
           (libtmux.internal::process-job-deadline (libtmux.internal::control-peer-job peer))))))

(test control-events-retain-order-and-report-overflow
  (let ((peer (local-control-peer :event-limit 2 :event-byte-limit 14)))
    (dolist (line '("%note A" "%note B" "%note C"))
      (libtmux.internal::consume-control-line peer (libtmux.internal::encode-utf8 line)))
    (let ((gap (libtmux.internal::next-control-event peer :timeout 0)))
      (is (eq :gap (getf gap :kind)))
      (is (= 1 (getf gap :events)))
      (is (= 7 (getf gap :bytes))))
    (is (equalp #(37 110 111 116 101 32 66)
                (getf (libtmux.internal::next-control-event peer :timeout 0) :data)))
    (is (equalp #(37 110 111 116 101 32 67)
                (getf (libtmux.internal::next-control-event peer :timeout 0) :data)))
    (multiple-value-bind (event delivery) (libtmux.internal::next-control-event peer :timeout 0)
      (is (null event))
      (is (eq :timeout delivery)))))

(test control-oversized-event-does-not-discard-retained-events
  (let ((peer (local-control-peer :event-limit 2 :event-byte-limit 14)))
    (dolist (line '("%note A" "%note B" "%note oversized"))
      (libtmux.internal::consume-control-line peer (libtmux.internal::encode-utf8 line)))
    (let ((gap (libtmux.internal::next-control-event peer :timeout 0)))
      (is (= 1 (getf gap :events)))
      (is (= 15 (getf gap :bytes))))
    (is (equalp #(37 110 111 116 101 32 65)
                (getf (libtmux.internal::next-control-event peer :timeout 0) :data)))
    (is (equalp #(37 110 111 116 101 32 66)
                (getf (libtmux.internal::next-control-event peer :timeout 0) :data)))))

(test control-request-capacity-includes-the-active-request
  (let ((peer (local-control-peer :request-limit 2)))
    (libtmux.internal::submit-control-command peer '("wait-for" "fixture") :effect :read)
    (libtmux.internal::control-supervisor-step peer (libtmux.internal::control-peer-job peer))
    (libtmux.internal::submit-control-command peer '("display-message" "-p" "queued") :effect :read)
    (signals libtmux:client-busy
      (libtmux.internal::submit-control-command peer '("display-message" "-p" "extra") :effect :read))
    (setf (libtmux.internal::control-peer-state peer) :closing)
    (signals libtmux:client-closed
      (libtmux.internal::submit-control-command peer '("display-message" "-p" "late") :effect :read))))

(test control-request-results-own-bytes-on-every-await
  (let* ((peer (local-control-peer))
         (request (libtmux.internal::submit-control-command peer '("display-message" "-p" "hello") :effect :read))
         (job (libtmux.internal::control-peer-job peer)))
    (libtmux.internal::control-supervisor-step peer job)
    (setf (libtmux.internal::process-job-offset job) (length (libtmux.internal::process-job-input job)))
    (let ((wire (libtmux.internal::encode-utf8
                 (format nil "%begin 1 8 1~%hello~%%end 1 8 1~%%begin 1 43 1~%~A~%%end 1 43 1~%"
                         (libtmux.internal::control-request-marker request)))))
      (libtmux.internal::append-bytes (aref (libtmux.internal::process-job-buffers job) 0) wire (length wire)))
    (libtmux.internal::control-supervisor-step peer job)
    (let ((first (libtmux.internal::await-control-request request :timeout 0)))
      (is (eq :completed (getf first :status)))
      (is (not (libtmux.internal::cancel-control-request request)))
      (is (eq t (getf first :dispatched-p)))
      (fill (getf first :output) 0))
    (is (equalp #(104 101 108 108 111 10)
                (getf (libtmux.internal::await-control-request request :timeout 0) :output)))))

(test control-eof-retains-partial-replies-and-closes-queued-requests
  (let* ((peer (local-control-peer :reply-byte-limit 4))
         (active (libtmux.internal::submit-control-command peer '("wait-for" "fixture") :effect :read))
         (queued (libtmux.internal::submit-control-command peer '("display-message" "-p" "unused") :effect :read)))
    (libtmux.internal::control-supervisor-step peer (libtmux.internal::control-peer-job peer))
    (libtmux.internal::append-bytes (libtmux.internal::control-request-output active) #(65 66) 2)
    (libtmux.internal::append-bytes (libtmux.internal::control-peer-frame peer) #(67 68 69) 3)
    (libtmux.internal::finish-control-peer peer)
    (is (equalp #(65 66 67 68)
                (getf (libtmux.internal::await-control-request active :timeout 0) :output)))
    (is (eq :closed (getf (libtmux.internal::await-control-request queued :timeout 0) :status)))
    (is (null (getf (libtmux.internal::await-control-request queued :timeout 0) :dispatched-p)))))

(test control-close-retains-an-unterminated-wire-tail
  (let* ((peer (local-control-peer))
         (request (libtmux.internal::submit-control-command peer '("wait-for" "fixture") :effect :read))
         (job (libtmux.internal::control-peer-job peer)))
    (libtmux.internal::control-supervisor-step peer job)
    (setf (libtmux.internal::process-job-offset job) 1)
    (libtmux.internal::feed-control-lines (libtmux.internal::control-peer-decoder peer)
                                         (libtmux.internal::octet-vector #(112 97 114 116)))
    (libtmux.internal::finish-control-peer peer)
    (let ((result (libtmux.internal::await-control-request request :timeout 0)))
      (is (equalp #(112 97 114 116) (getf result :wire-tail)))
      (is (eq t (getf result :dispatched-p))))))

(test control-close-recovers-an-already-aborted-worker
  (let ((peer (local-control-peer)))
    (setf (libtmux.internal::control-peer-worker peer)
          (sb-thread:make-thread (lambda () (sb-thread:abort-thread))))
    (unwind-protect
         (progn
           (libtmux.internal::close-control-peer peer)
           (is (libtmux.internal::control-peer-finished peer))
           (is (typep (libtmux.internal::control-peer-failure peer) 'libtmux:command-failed))
           (is (not (find peer libtmux.internal::*pending-control-peers*))))
      (when (sb-thread:thread-alive-p (libtmux.internal::control-peer-worker peer))
        (sb-thread:terminate-thread (libtmux.internal::control-peer-worker peer))))))

(test control-reply-line-count-does-not-undercut-its-byte-limit
  (let* ((peer (local-control-peer :reply-byte-limit 8192))
         (request (libtmux.internal::submit-control-command peer '("capture-pane" "-p") :effect :read))
         (job (libtmux.internal::control-peer-job peer)))
    (libtmux.internal::control-supervisor-step peer job)
    (setf (libtmux.internal::process-job-offset job) (length (libtmux.internal::process-job-input job)))
    (let ((wire (libtmux.internal::encode-utf8
                 (format nil "%begin 1 8 1~%~A%end 1 8 1~%%begin 1 43 1~%~A~%%end 1 43 1~%"
                         (make-string 5000 :initial-element #\Newline)
                         (libtmux.internal::control-request-marker request)))))
      (libtmux.internal::append-bytes (aref (libtmux.internal::process-job-buffers job) 0) wire (length wire)))
    (libtmux.internal::control-supervisor-step peer job)
    (let ((result (libtmux.internal::await-control-request request :timeout 0)))
      (is (eq :completed (getf result :status)))
      (is (= 5000 (length (getf result :output))))
      (is (every (lambda (byte) (= byte 10)) (getf result :output))))))

(test control-timeout-status-survives-a-late-completion-marker
  (let* ((peer (local-control-peer))
         (request (libtmux.internal::submit-control-command peer '("wait-for" "fixture") :effect :read))
         (job (libtmux.internal::control-peer-job peer)))
    (libtmux.internal::control-supervisor-step peer job)
    (setf (libtmux.internal::process-job-offset job) (length (libtmux.internal::process-job-input job))
          (libtmux.internal::control-request-deadline request) 0)
    (libtmux.internal::control-supervisor-step peer job)
    (is (eq :timed-out (getf (libtmux.internal::await-control-request request :timeout 0) :status)))
    (let ((wire (libtmux.internal::encode-utf8
                 (format nil "%begin 1 8 1~%late~%%end 1 8 1~%%begin 1 43 1~%~A~%%end 1 43 1~%"
                         (libtmux.internal::control-request-marker request)))))
      (libtmux.internal::append-bytes (aref (libtmux.internal::process-job-buffers job) 0) wire (length wire)))
    (libtmux.internal::control-supervisor-step peer job)
    (let ((result (libtmux.internal::await-control-request request :timeout 0)))
      (is (eq :timed-out (getf result :status)))
      (is (equalp #(108 97 116 101 10) (getf result :output))))))

(test control-finalization-retains-a-supervisor-deadline
  (let* ((peer (local-control-peer))
         (request (libtmux.internal::submit-control-command peer '("wait-for" "fixture") :effect :read))
         (job (libtmux.internal::control-peer-job peer)))
    (libtmux.internal::control-supervisor-step peer job)
    (setf (libtmux.internal::process-job-reason job) :deadline)
    (libtmux.internal::finish-control-peer peer)
    (let ((result (libtmux.internal::await-control-request request :timeout 0)))
      (is (eq :timed-out (getf result :status)))
      (is (eq :deadline (getf result :reason))))))

(test control-cancellation-preserves-queue-and-dispatch-evidence
  (let* ((peer (local-control-peer))
         (active (libtmux.internal::submit-control-command peer '("wait-for" "held") :effect :read))
         (queued (libtmux.internal::submit-control-command peer '("display-message" "-p" "unused") :effect :read))
         (job (libtmux.internal::control-peer-job peer)))
    (libtmux.internal::control-supervisor-step peer job)
    (is (libtmux.internal::cancel-control-request queued))
    (is (not (libtmux.internal::cancel-control-request queued)))
    (let ((result (libtmux.internal::await-control-request queued :timeout 0)))
      (is (eq :cancelled (getf result :status)))
      (is (eq :not-dispatched (getf result :reason)))
      (is (null (getf result :dispatched-p))))
    (is (eq :ready (libtmux.internal::control-peer-state peer)))
    (setf (libtmux.internal::process-job-offset job) 1)
    (is (libtmux.internal::cancel-control-request active))
    (libtmux.internal::finish-control-peer peer)
    (let ((result (libtmux.internal::await-control-request active :timeout 0)))
      (is (eq :cancelled (getf result :status)))
      (is (eq :cancelled (getf result :reason)))
      (is (eq t (getf result :dispatched-p))))
    (is (not (libtmux.internal::cancel-control-request active)))))

(test control-cancellation-survives-a-late-completion-marker
  (let* ((peer (local-control-peer))
         (request (libtmux.internal::submit-control-command peer '("display-message" "-p" "late") :effect :read))
         (job (libtmux.internal::control-peer-job peer)))
    (libtmux.internal::control-supervisor-step peer job)
    (setf (libtmux.internal::process-job-offset job) (length (libtmux.internal::process-job-input job)))
    (is (libtmux.internal::cancel-control-request request))
    (let ((wire (libtmux.internal::encode-utf8
                 (format nil "%begin 1 8 1~%late~%%end 1 8 1~%%begin 1 43 1~%~A~%%end 1 43 1~%"
                         (libtmux.internal::control-request-marker request)))))
      (libtmux.internal::append-bytes (aref (libtmux.internal::process-job-buffers job) 0) wire (length wire)))
    (libtmux.internal::control-supervisor-step peer job)
    (is (eq :cancelled (getf (libtmux.internal::await-control-request request :timeout 0) :status)))
    (libtmux.internal::finish-control-peer peer)
    (is (eq :cancelled (getf (libtmux.internal::await-control-request request :timeout 0) :status)))))

(test control-worker-stops-input-before-publishing-cancellation
  (let* ((peer (local-control-peer))
         (request (libtmux.internal::submit-control-command peer '("display-message" "-p" "held") :effect :read))
         (job (libtmux.internal::control-peer-job peer)))
    (libtmux.internal::control-supervisor-step peer job)
    ;; Model the caller after publishing intent but before cancelling the token.
    (setf (libtmux.internal::control-request-cancel-requested request) t
          (libtmux.internal::control-peer-state peer) :closing
          (libtmux.internal::process-job-input-fd job) :unwritten-fixture)
    (is (not (libtmux:cancelled-p (libtmux.internal::process-job-token job))))
    (libtmux.internal::control-supervisor-step peer job)
    (let ((result (libtmux.internal::await-control-request request :timeout 0)))
      (is (eq :cancelled (getf result :status)))
      (is (not (getf result :dispatched-p))))
    (is (not (null (libtmux.internal::process-job-final-at job))))
    (is (null (libtmux.internal::process-job-input-fd job)))))

(test control-close-preserves-an-already-delivered-end-reason
  (dolist (reason '(:eof :deadline :cancelled))
    (let ((peer (local-control-peer :finished t)))
      (setf (libtmux.internal::control-peer-state peer) :closed
            (libtmux.internal::process-job-reason (libtmux.internal::control-peer-job peer)) reason)
      (is (eq reason (getf (libtmux.internal::next-control-event peer :timeout 0) :reason)))
      (libtmux.internal::close-control-peer peer)
      (is (eq reason (getf (libtmux.internal::next-control-event peer :timeout 0) :reason))))))
