(in-package #:libtmux.internal)

(defstruct (control-peer (:constructor %make-control-peer))
  "Private persistent connection; one worker owns all process and protocol I/O."
  (lock (make-lock "tmux control")) (changed (make-condition-variable))
  (close-lock (make-lock "tmux control close"))
  job worker wake (state :starting) finished stop-requested failure
  (key (symbol-name (gensym "LIBTMUX-CONTROL-"))) (serial 0) ready-marker
  decoder header (frame (byte-buffer)) (wire-tail (octet-vector nil))
  (pending nil) active
  (request-limit 16) (reply-byte-limit 1048576)
  (events nil) (event-count 0) (event-bytes 0)
  (event-limit 256) (event-byte-limit 4194304)
  (dropped-events 0) (dropped-bytes 0)
  (diagnostics (byte-buffer)))

(defstruct control-request
  "Private queued request with owned arguments, accumulated replies and state."
  peer arguments effect marker deadline
  (state :queued) dispatched reason (output (byte-buffer)) (replies 0) failed
  (wire-tail (octet-vector nil)) truncated)

(define-condition control-start-failed (libtmux:command-failed)
  ((peer :initarg :peer :reader failed-control-peer))
  (:documentation "Control startup failed; retain its peer for cleanup recovery."))

(defvar *pending-control-peers* nil)
(defvar *pending-control-lock* (make-lock "pending control cleanup"))

(defun retain-control-peer (peer)
  (call-with-lock *pending-control-lock* (lambda () (pushnew peer *pending-control-peers*))))

(defun forget-control-peer (peer)
  (call-with-lock *pending-control-lock*
                  (lambda () (setf *pending-control-peers* (remove peer *pending-control-peers*)))))

(defun with-control-lock (peer function)
  (call-with-lock (control-peer-lock peer) function))

(defun control-marker-input (marker)
  (format nil "~A~%" (tmux-command-text (list "display-message" "-p" "-l" marker))))

(defun control-request-result (request)
  (list :status (control-request-state request)
        :output (copy-seq (control-request-output request))
        :wire-tail (copy-seq (control-request-wire-tail request))
        :truncated-p (control-request-truncated request)
        :effect (control-request-effect request)
        :dispatched-p (control-request-dispatched request)
        :reason (control-request-reason request)
        :reply-count (control-request-replies request)))

(defun wait-control-value (peer function timeout)
  (when timeout (check-limits timeout 1))
  (let ((deadline (and timeout (+ (monotonic-seconds) timeout))))
    (with-control-lock
     peer
     (lambda ()
       (loop for value = (funcall function)
             for remaining = (and deadline (- deadline (monotonic-seconds)))
             when value return (values value :ready)
             when (and remaining (<= remaining 0)) return (values nil :timeout)
             do (condition-wait (control-peer-changed peer) (control-peer-lock peer) remaining))))))

(defun await-control-request (request &key (timeout 30))
  "Wait for a request result; return owned result/:READY or NIL/:TIMEOUT.
A wait timeout leaves the request live. Result status describes the command
queue and retains dispatch evidence; it does not establish application readiness."
  (check-type request control-request)
  (wait-control-value
   (control-request-peer request)
   (lambda ()
     (unless (member (control-request-state request) '(:queued :writing :running))
       (control-request-result request))) timeout))

(defun next-control-event (peer &key (timeout 30))
  "Return the next owned event/:READY, or NIL/:TIMEOUT while still open.
Pane output is bytes. :GAP reports dropped event and byte counts; :END follows
retained events after the worker closes. Application callbacks are not run."
  (check-type peer control-peer)
  (wait-control-value
   peer
   (lambda ()
     (cond
       ((plusp (control-peer-dropped-events peer))
        (prog1 (list :kind :gap :events (control-peer-dropped-events peer)
                     :bytes (control-peer-dropped-bytes peer))
          (setf (control-peer-dropped-events peer) 0 (control-peer-dropped-bytes peer) 0)))
       ((control-peer-events peer)
        (let ((event (pop (control-peer-events peer))))
          (decf (control-peer-event-count peer))
          (decf (control-peer-event-bytes peer) (length (getf event :data)))
          event))
       ((control-peer-finished peer)
        (list :kind :end :reason (if (control-peer-stop-requested peer) :closed
                                    (or (and (control-peer-job peer)
                                             (process-job-reason (control-peer-job peer))) :eof))
              :exit-code (and (control-peer-job peer) (process-job-code (control-peer-job peer)))
              :diagnostics (copy-seq (control-peer-diagnostics peer))
              :wire-tail (copy-seq (control-peer-wire-tail peer))
              :cause (control-peer-failure peer))))) timeout))

(defun ensure-control-decoder (peer)
  (or (control-peer-decoder peer)
      (setf (control-peer-decoder peer)
            (make-control-line-decoder
             :line-byte-limit (max (control-peer-reply-byte-limit peer)
                                   (+ 128 (* 4 (control-peer-event-byte-limit peer))))
             :batch-byte-limit 65536 :batch-line-limit 65536))))

(defun capture-control-wire-tail (peer)
  (let* ((decoder (control-peer-decoder peer))
         (pending (and decoder (control-line-decoder-pending decoder))))
    (when (and pending (plusp (length pending)))
      (setf (control-peer-wire-tail peer) (copy-seq pending)))))

(defun enqueue-control-event (peer event)
  (let ((size (length (getf event :data))))
    (when (> size (control-peer-event-byte-limit peer))
      (incf (control-peer-dropped-events peer))
      (incf (control-peer-dropped-bytes peer) size)
      (return-from enqueue-control-event nil))
    (loop while (and (control-peer-events peer)
                     (or (>= (control-peer-event-count peer) (control-peer-event-limit peer))
                         (> (+ size (control-peer-event-bytes peer)) (control-peer-event-byte-limit peer))))
          for dropped = (pop (control-peer-events peer))
          do (decf (control-peer-event-count peer))
             (let ((bytes (length (getf dropped :data))))
               (decf (control-peer-event-bytes peer) bytes)
               (incf (control-peer-dropped-events peer))
               (incf (control-peer-dropped-bytes peer) bytes)))
    (setf (control-peer-events peer) (nconc (control-peer-events peer) (list event)))
    (incf (control-peer-event-count peer))
    (incf (control-peer-event-bytes peer) size)))

(defun control-begin-header (line)
  (when (and (<= (length line) 100) (byte-prefix-p (encode-utf8 "%begin ") line))
    (handler-case
        (let ((parts (uiop:split-string (decode-utf8 line) :separator '(#\Space))))
          (when (= 4 (length parts))
            (let ((numbers (mapcar #'parse-integer (rest parts))))
              (when (and (typep (first numbers) '(signed-byte 64))
                         (typep (second numbers) '(unsigned-byte 32))
                         (member (third numbers) '(0 1)))
                numbers))))
      (parse-error () nil))))

(defun append-control-reply (peer request bytes)
  (when (> (+ (length (control-request-output request)) (length bytes))
           (control-peer-reply-byte-limit peer))
    (error 'libtmux:output-limit-exceeded :message "Control request exceeded its reply byte limit"))
  (append-bytes (control-request-output request) bytes (length bytes)))

(defun complete-control-frame (peer failed-p)
  (let ((bytes (copy-seq (control-peer-frame peer)))
        (request (control-peer-active peer)))
    (cond
      ((and (eq (control-peer-state peer) :starting)
            (equalp bytes (encode-utf8 (format nil "~A~%" (control-peer-ready-marker peer))))
            (not failed-p))
       (when (libtmux:cancelled-p (process-job-token (control-peer-job peer)))
         (error 'libtmux:command-cancelled :message "Control startup was cancelled"))
       (when (>= (monotonic-seconds) (process-job-deadline (control-peer-job peer)))
         (error 'libtmux:deadline-exceeded :message "Control startup exceeded its deadline"))
       (setf (control-peer-state peer) :ready
             (process-job-deadline (control-peer-job peer)) nil))
      ((eq (control-peer-state peer) :starting)
       (when failed-p
         (error 'libtmux:command-failed :message "Control session attachment failed")))
      ((and request (not failed-p)
            (equalp bytes (encode-utf8 (format nil "~A~%" (control-request-marker request)))))
       (when (member (control-request-state request) '(:queued :writing :running))
         (setf (control-request-state request) (if (control-request-failed request) :failed :completed)))
       (setf (control-peer-active peer) nil
             (process-job-deadline (control-peer-job peer)) nil))
      (request
       (when (> (incf (control-request-replies request)) 4096)
         (error 'libtmux:output-limit-exceeded :message "Control request exceeded its reply frame limit"))
       (append-control-reply peer request bytes)
       (when failed-p (setf (control-request-failed request) t)))
      (t (enqueue-control-event peer (list :kind :reply :data bytes :failed-p failed-p))))
    (setf (control-peer-header peer) nil (fill-pointer (control-peer-frame peer)) 0)))

(defun consume-control-line (peer line)
  (let ((header (control-peer-header peer)))
    (cond
      (header
       (cond
         ((equalp line (encode-utf8 (format nil "%end ~{~D~^ ~}" header)))
          (complete-control-frame peer nil))
         ((equalp line (encode-utf8 (format nil "%error ~{~D~^ ~}" header)))
          (complete-control-frame peer t))
         (t
          (when (> (+ (length (control-peer-frame peer)) (length line) 1)
                   (control-peer-reply-byte-limit peer))
            (error 'libtmux:output-limit-exceeded :message "Control frame exceeded its byte limit"))
          (append-bytes (control-peer-frame peer) line (length line))
          (vector-push-extend 10 (control-peer-frame peer)))))
      ((control-begin-header line)
       (setf (control-peer-header peer) (control-begin-header line)))
      ((or (byte-prefix-p (encode-utf8 "%output ") line)
           (byte-prefix-p (encode-utf8 "%extended-output ") line))
       (let ((wire-limit (control-line-decoder-line-byte-limit (ensure-control-decoder peer))))
         (multiple-value-bind (bytes pane age extended-p)
             (decode-control-output-line line :line-byte-limit wire-limit :byte-limit wire-limit)
           (enqueue-control-event peer (list :kind :output :pane pane :age age
                                             :extended-p extended-p :data bytes)))))
      (t (enqueue-control-event peer (list :kind :notification :data line))))))

(defun submit-control-command (peer arguments &key effect (timeout 30))
  "Queue copied native argv and return immediately with a private request.
EFFECT must be :READ or :MUTATION. TIMEOUT covers queueing and execution; an
in-flight deadline closes this connection and retains partial replies."
  (check-type peer control-peer)
  (unless (member effect '(:read :mutation)) (invalid-argument "Specify control command effect :read or :mutation"))
  (check-limits timeout 1)
  (let* ((arguments (argument-vector arguments))
         (text (tmux-command-text arguments)))
    (unless (plusp (length arguments)) (invalid-argument "A control command is required"))
    (when (> (length (encode-utf8 text)) 16000)
      (invalid-argument "Control command exceeds 16,000 encoded bytes"))
    (with-control-lock
     peer
     (lambda ()
       (unless (eq (control-peer-state peer) :ready)
         (error 'libtmux:client-closed :message "Control connection is closing or closed"))
       (when (>= (+ (length (control-peer-pending peer)) (if (control-peer-active peer) 1 0))
                 (control-peer-request-limit peer))
         (error 'libtmux:client-busy :message "Control request queue is full"))
       (let ((request (make-control-request
                       :peer peer :arguments arguments :effect effect
                       :deadline (+ (monotonic-seconds) timeout)
                       :marker (format nil "~A-~D" (control-peer-key peer) (incf (control-peer-serial peer))))))
         (setf (control-peer-pending peer) (nconc (control-peer-pending peer) (list request)))
         (when (control-peer-wake peer) (wake-operation (control-peer-wake peer)))
         request)))))

(defun control-supervisor-step (peer job)
  (with-control-lock
   peer
   (lambda ()
     (let ((request (control-peer-active peer)))
       (when (and request (plusp (process-job-offset job)))
         (setf (control-request-dispatched request) t)
         (when (member (control-request-state request) '(:queued :writing :running))
           (setf (control-request-state request) :running))))
     (let ((stdout (aref (process-job-buffers job) 0))
           (stderr (aref (process-job-buffers job) 1)))
       (when (plusp (length stdout))
         (loop for line across (feed-control-lines (ensure-control-decoder peer) stdout)
               do (consume-control-line peer line))
         (setf (fill-pointer stdout) 0))
       (when (> (+ (length stderr) (length (control-peer-diagnostics peer))) 65536)
         (error 'libtmux:output-limit-exceeded :message "Control diagnostics exceeded 64 KiB"))
       (append-bytes (control-peer-diagnostics peer) stderr (length stderr))
       (setf (fill-pointer stderr) 0 (process-job-total job) 0))
     (let ((request (control-peer-active peer)))
       (when (and request (member (control-request-state request) '(:queued :writing :running))
                  (>= (monotonic-seconds) (control-request-deadline request)))
         (setf (control-request-state request) :timed-out
               (control-request-reason request) :deadline
               (control-peer-state peer) :closing)
         (stop-job job :request-timeout)))
     (let ((now (monotonic-seconds)))
       (setf (control-peer-pending peer)
             (delete-if (lambda (request)
                          (when (>= now (control-request-deadline request))
                            (setf (control-request-state request) :timed-out
                                  (control-request-reason request) :deadline)
                            t))
                        (control-peer-pending peer))))
     (when (and (eq (control-peer-state peer) :ready) (not (control-peer-active peer))
                (= (process-job-offset job) (length (process-job-input job))))
       (loop while (control-peer-pending peer)
             for request = (pop (control-peer-pending peer))
             do (if (>= (monotonic-seconds) (control-request-deadline request))
                    (setf (control-request-state request) :timed-out
                          (control-request-reason request) :deadline)
                    (progn
                      (setf (control-peer-active peer) request
                            (control-request-state request) :writing
                            (process-job-input job)
                            (encode-utf8 (concatenate 'string
                                                     (format nil "~A~%" (tmux-command-text (control-request-arguments request)))
                                                     (control-marker-input (control-request-marker request))))
                            (process-job-offset job) 0
                            (process-job-deadline job) (control-request-deadline request))
                      (return)))))
     (when (eq (control-peer-state peer) :ready)
       (let ((queued (mapcar #'control-request-deadline (control-peer-pending peer))))
         (setf (process-job-deadline job) (and (control-peer-active peer)
                                              (control-request-deadline (control-peer-active peer)))
               (process-job-poll-deadline job) (and queued (apply #'min queued)))))
     (condition-broadcast (control-peer-changed peer)))))

(defun finish-control-peer (peer)
  (capture-control-wire-tail peer)
  (let ((active (control-peer-active peer)))
    (when active
      (when (plusp (process-job-offset (control-peer-job peer)))
        (setf (control-request-dispatched active) t))
      (when (plusp (length (control-peer-frame peer)))
        (let* ((frame (control-peer-frame peer))
               (remaining (- (control-peer-reply-byte-limit peer) (length (control-request-output active)))))
          (append-bytes (control-request-output active) frame (min remaining (length frame)))
          (when (> (length frame) remaining) (setf (control-request-truncated active) t))))
      (let* ((tail (control-peer-wire-tail peer))
             (remaining (- (control-peer-reply-byte-limit peer) (length (control-request-output active)))))
        (setf (control-request-wire-tail active) (subseq tail 0 (min remaining (length tail))))
        (when (> (length tail) remaining) (setf (control-request-truncated active) t)))
      (unless (eq (control-request-state active) :timed-out)
        (let ((reason (process-job-reason (control-peer-job peer))))
          (if (member reason '(:deadline :request-timeout))
              (setf (control-request-state active) :timed-out (control-request-reason active) :deadline)
              (setf (control-request-state active) :closed
                    (control-request-reason active)
                    (or reason (if (control-peer-stop-requested peer) :cancelled :eof)))))))
    (dolist (request (control-peer-pending peer))
      (setf (control-request-state request) :closed (control-request-reason request) :not-dispatched))
    (setf (control-peer-active peer) nil (control-peer-pending peer) nil)))

(defun run-control-supervisor (peer)
  (let ((job (control-peer-job peer)) (failure nil))
    (unwind-protect
         (handler-case
             (progn
               (when (acquire-job job)
                 (with-control-lock peer (lambda () (setf (control-peer-wake peer) (process-job-wake job))))
                 (supervise-job job :before-step (lambda (owned) (control-supervisor-step peer owned))))
               (with-control-lock peer (lambda () (capture-control-wire-tail peer)))
               (unless (or (control-peer-stop-requested peer) (process-job-reason job))
                 (finish-control-lines (ensure-control-decoder peer))))
           (error (condition) (setf failure condition)))
      (with-control-lock
       peer (lambda ()
              (setf (control-peer-wake peer) nil (control-peer-state peer) :closing
                    (control-peer-failure peer) failure)
              (handler-case (finish-control-peer peer)
                (error (condition) (setf (control-peer-failure peer) (or failure condition))))))
      (unwind-protect
           (handler-case
               (unless (cleanup-job job) (retain-control-peer peer))
             (error (condition)
               (retain-control-peer peer)
               (with-control-lock peer (lambda () (setf (control-peer-failure peer) condition)))))
        (with-control-lock
         peer (lambda ()
                (setf (control-peer-finished peer) t (control-peer-state peer) :closed)
                (condition-broadcast (control-peer-changed peer))))))))

(defun %close-control-peer (peer)
  "Cancel and join this private connection, leaving its tmux daemon running.
Unfinished requests retain partial bytes and dispatch state. Retry this call
if CLEANUP-FAILED retains resources. Repeated successful close is harmless."
  (check-type peer control-peer)
  (with-control-lock
   peer (lambda () (setf (control-peer-stop-requested peer) t)
          (unless (control-peer-finished peer) (setf (control-peer-state peer) :closing))))
  (when (control-peer-job peer) (libtmux:cancel (process-job-token (control-peer-job peer))))
  (when (and (control-peer-worker peer)
             (not (eq (control-peer-worker peer) (current-thread))))
    (multiple-value-bind (value reason)
        (sb-thread:join-thread (control-peer-worker peer) :timeout 0.75 :default :not-joined)
      (declare (ignore value))
      (when (and (eq reason :timeout) (sb-thread:thread-alive-p (control-peer-worker peer)))
        (error 'libtmux:cleanup-failed :resource peer :message "Control worker has not completed cleanup"))
      (when (eq reason :abort)
        (with-control-lock
         peer (lambda ()
                (setf (control-peer-failure peer)
                      (or (control-peer-failure peer)
                          (make-condition 'libtmux:command-failed :message "Control worker aborted; retrying cleanup"))))))))
  (let ((job (control-peer-job peer)))
    (when (and job (or (process-job-pidfd job) (process-job-directory job)
                      (process-job-cleanup-failures job)))
      (setf (process-job-cleanup-failures job) nil)
      (unless (cleanup-job job)
        (retain-control-peer peer)
        (error 'libtmux:cleanup-failed :resource peer :message "Control process still owns cleanup work"))
      (when (process-job-cleanup-failures job)
        (retain-control-peer peer)
        (error 'libtmux:cleanup-failed :resource peer :cause (first (process-job-cleanup-failures job))
               :message "Control cleanup failed; retry closing the connection"))))
  (with-control-lock
   peer (lambda ()
          (finish-control-peer peer)
          (setf (control-peer-finished peer) t (control-peer-state peer) :closed)
          (condition-broadcast (control-peer-changed peer))))
  (forget-control-peer peer)
  nil)

(defun close-control-peer (peer)
  "Cancel and join this separate resource; leave its tmux daemon running.
Concurrent close calls serialize. Unfinished requests retain dispatch and
partial replies. A failed close retains the peer for a later cleanup retry."
  (check-type peer control-peer)
  (handler-case
      (progn
        (when (eq (control-peer-worker peer) (current-thread))
          (error 'libtmux:cleanup-failed :resource peer :message "A control worker cannot join itself"))
        (call-with-lock (control-peer-close-lock peer) (lambda () (%close-control-peer peer))))
    (error (condition)
      (retain-control-peer peer)
      (error condition))))

(defun start-control-peer (client session &key (timeout 30) (request-limit 16)
                                              (event-limit 256) (event-byte-limit 4194304)
                                              (reply-byte-limit 1048576))
  "Open a private persistent control connection to a captured session.
Preflight once, then use one owned worker for queued commands and events.
The live daemon must be 3.7 or newer. Closing CLIENT does not close this
separate resource; close the returned peer explicitly. No application callback runs."
  (check-type client libtmux:client)
  (check-type session libtmux:session)
  (check-limits timeout reply-byte-limit)
  (unless (and (typep request-limit '(integer 1)) (typep event-limit '(integer 1))
               (typep event-byte-limit '(integer 1)))
    (invalid-argument "Control queue limits must be positive integers"))
  (call-with-operation
   client nil
   (lambda (token)
     (let* ((start (monotonic-seconds))
            (budget (make-capture-budget :start start :deadline (+ start timeout)
                                         :remaining (slot-value client 'libtmux::output-limit)
                                         :row-limit 100000 :field-limit 1048576))
            (current (first (preflight-targets client (list session) token budget))))
       (check-command-capability client :control "3.7")
       (let* ((*command-socket-path* (server-witness-endpoint (slot-value client 'libtmux::witness)))
              (peer (%make-control-peer :request-limit request-limit :event-limit event-limit
                                        :event-byte-limit event-byte-limit :reply-byte-limit reply-byte-limit))
              (returned nil) (primary nil))
         (setf (control-peer-ready-marker peer) (format nil "~A-READY" (control-peer-key peer))
               (control-peer-job peer)
               (make-process-job :argv (argument-vector (client-argv client (list "-N" "-C" "attach-session" "-t" (libtmux:id current))))
                                 :input (encode-utf8 (control-marker-input (control-peer-ready-marker peer)))
                                 :keep-input-open t :environment (process-environment)
                                 :token token :cap 1048576 :start start :deadline (capture-budget-deadline budget)))
         (unwind-protect
              (handler-case
                  (progn
                    (let ((launched *process-launched-hook*) (dispatch *before-dispatch-hook*)
                          (started *process-started-hook*))
                      (setf (control-peer-worker peer)
                            (sb-thread:make-thread
                             (lambda ()
                               (let ((*process-launched-hook* launched) (*before-dispatch-hook* dispatch)
                                     (*process-started-hook* started))
                                 (run-control-supervisor peer))) :name "tmux control")))
                    (multiple-value-bind (state delivery)
                        (wait-control-value peer (lambda ()
                                                   (when (or (eq (control-peer-state peer) :ready) (control-peer-finished peer))
                                                     (control-peer-state peer)))
                                            (max 0 (- (capture-budget-deadline budget) (monotonic-seconds))))
                      (unless (and (eq delivery :ready) (eq state :ready))
                        (error (or (control-peer-failure peer)
                                   (make-condition 'libtmux:deadline-exceeded :message "Control connection did not become ready")))))
                    (setf returned t))
                (error (condition) (setf primary condition)))
           (unless returned
             (handler-case (close-control-peer peer)
               (error (condition)
                 (setf primary (or primary condition) (control-peer-failure peer) condition)
                 (retain-control-peer peer)))))
         (when primary
           (error 'control-start-failed :peer peer :cause primary
                  :message "Control startup failed; inspect its retained cause and peer"))
         peer)))))
