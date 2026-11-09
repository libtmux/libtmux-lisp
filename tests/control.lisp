(in-package #:libtmux.tests)

(in-suite control)

(defun local-control-connection (&rest options)
  (libtmux.control::%connection-for-peer (apply #'local-control-peer options)))

(defclass admission-control-connection (libtmux.control:connection)
  ((closes :initform 0 :accessor admission-closes)))

(defmethod libtmux.control:close-connection :before ((connection admission-control-connection))
  (incf (admission-closes connection)))

(test control-admission-refuses-legacy-live-witness-before-cutover
  (let ((capture-function (symbol-function 'libtmux.internal::capture-with-retries))
        (attach-function (symbol-function 'libtmux.internal::attach-control-peer))
        (active-client nil) (capture nil) (witness nil) (attachments 0) (candidates nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'libtmux.internal::capture-with-retries)
                 (lambda (client token budget limit)
                   (declare (ignore token budget limit))
                   (assert (eq client active-client))
                   (setf (slot-value client 'libtmux::witness) witness)
                   capture)
                 (symbol-function 'libtmux.internal::attach-control-peer)
                 (lambda (&rest arguments)
                   (declare (ignore arguments))
                   (incf attachments)
                   (let ((peer (local-control-peer))) (push peer candidates) peer)))
           (dolist (version '("3.7" "3.7a" "3.7b" "3.7c"))
             (let* ((client (make-instance 'libtmux:client))
                    (context (slot-value client 'libtmux::context))
                    (generation (slot-value client 'libtmux::generation)))
               (setf active-client client attachments 0
                     capture (synthetic-snapshot :context context :generation generation)
                     witness (libtmux.internal::make-server-witness :version version)
                     (slot-value client 'libtmux::witness) witness
                     (slot-value client 'libtmux::version) "3.8")
               (let* ((peer (local-control-peer :origin-client client :origin-context context
                              :origin-generation generation :origin-session "$1"
                              :origin-witness (libtmux.internal::witness-values witness)))
                      (old (make-instance 'admission-control-connection :peer peer)))
                 (unwind-protect
                      (progn
                        (dolist (operation (list (lambda () (libtmux.control:open-connection
                                                           client (aref (libtmux:sessions capture) 0)))
                                                 (lambda () (libtmux.control:reconnect old))))
                          (let ((failure (handler-case (progn (funcall operation) nil)
                                           (error (condition) condition))))
                            (is (typep failure 'libtmux:unsupported-capability))
                            (when (typep failure 'libtmux:unsupported-capability)
                              (is (string= "3.8" (libtmux:error-required-version failure)))
                              (is (string= version (libtmux:error-actual-version failure)))))
                          (is (zerop attachments))
                          (is (zerop (admission-closes old)))
                          (is (= generation (slot-value client 'libtmux::generation)))))
                   (libtmux.control:close-connection old)
                   (libtmux:close-client client))))))
      (setf (symbol-function 'libtmux.internal::capture-with-retries) capture-function
            (symbol-function 'libtmux.internal::attach-control-peer) attach-function)
      (dolist (peer candidates) (libtmux.internal::close-control-peer peer)))))

(test control-cleanup-does-not-transfer-ownership-to-a-core-operation
  (let* ((client (make-instance 'libtmux:client))
         (connection (local-control-connection))
         (peer (libtmux.control::%peer connection))
         (job (libtmux.internal::control-peer-job peer))
         (directory (sb-posix:mkdtemp "/tmp/libtmux-control-owner-XXXXXX"))
         (held (merge-pathnames "held" (uiop:ensure-directory-pathname directory))))
    (unwind-protect
         (progn
           (with-open-file (stream held :direction :output :if-exists :error)
             (write-string "keep directory nonempty" stream))
           (setf (libtmux.internal::process-job-directory job) directory)
           (let ((libtmux.internal::*operation-client* client))
             (signals libtmux.control:connection-cleanup-failed
               (libtmux.control:close-connection connection)))
           (is (find connection (libtmux.control:pending-cleanups)))
           (is (libtmux:client-open-p client))
           (is (null (slot-value client 'libtmux::cleanup-jobs)))
           (is (zerop (length (libtmux:client-cleanup-failures client)))))
      (when (probe-file held) (delete-file held))
      (let ((libtmux.internal::*operation-client* nil))
        (libtmux.control:close-connection connection))
      (libtmux:close-client client))))

(test control-public-resource-identity-and-conditions
  (let* ((connection (local-control-connection :request-limit 1))
         (peer (libtmux.control::%peer connection)))
    (is (eq connection (libtmux.control::%connection-for-peer peer)))
    (is (typep connection 'standard-object))
    (let ((request (libtmux.control:submit-command connection '("wait-for" "held") :effect :read)))
      (is (typep request 'libtmux.control:request))
      (is (eq :queued (libtmux.control:request-state request))))
    (handler-case (libtmux.control:submit-command connection '("display-message" "-p" "full") :effect :read)
      (libtmux.control:connection-busy (condition)
        (is (eq connection (libtmux.control:error-connection condition)))
        (is (typep (libtmux:error-cause condition) 'libtmux:client-busy))))
    (signals libtmux:invalid-argument
      (libtmux.control:submit-command connection '("display-message" "-p" "bad")))
    (libtmux.control:close-connection connection)
    (is (eq :closed (libtmux.control:connection-state connection)))
    (signals libtmux.control:connection-closed
      (libtmux.control:submit-command connection '("display-message" "-p" "closed") :effect :read))))

(test control-public-scope-preserves-original-values-and-special-declarations
  (let ((original (local-control-connection)) (replacement (local-control-connection)))
    (flet ((libtmux.control:open-connection (client session)
             (declare (ignore client session)) original))
      (is (equal '(1 nil :tail)
                 (multiple-value-list
                  (libtmux.control:with-connection (resource nil nil)
                    (declare (special resource))
                    (is (eq original (symbol-value 'resource)))
                    (setf resource replacement)
                    (values 1 nil :tail))))))
    (is (eq :closed (libtmux.control:connection-state original)))
    (is (eq :ready (libtmux.control:connection-state replacement)))
    (libtmux.control:close-connection replacement)))

(defclass failing-control-close (libtmux.control:connection)
  ((failure :initarg :failure :reader control-close-failure)))

(defmethod libtmux.control:close-connection ((connection failing-control-close))
  (error (control-close-failure connection)))

(test control-public-scope-retains-secondary-cleanup-failures
  (let* ((primary (make-condition 'simple-error :format-control "primary"))
         (secondary (make-condition 'simple-error :format-control "cleanup"))
         (connection (make-instance 'failing-control-close :peer (local-control-peer) :failure secondary)))
    (flet ((libtmux.control:open-connection (client session)
             (declare (ignore client session)) connection))
      (is (eq primary
              (handler-case
                  (libtmux.control:with-connection (resource nil nil)
                    (declare (ignore resource)) (error primary))
                (simple-error (condition) condition))))
      (is (eq :left
              (catch 'leave
                (libtmux.control:with-connection (resource nil nil)
                  (declare (ignore resource)) (throw 'leave :left)))))
      (is (eq secondary (aref (libtmux.control:connection-cleanup-failures connection) 0)))
      (is (eq secondary
              (handler-case
                  (libtmux.control:with-connection (resource nil nil) (declare (ignore resource)) :normal)
                (simple-error (condition) condition)))))
    (libtmux.internal::close-control-peer (libtmux.control::%peer connection))))

(test control-public-failed-cleanup-retains-recoverable-resource
  (let* ((connection (local-control-connection))
         (peer (libtmux.control::%peer connection)))
    (unwind-protect
         (progn
           (setf (libtmux.internal::control-peer-worker peer) sb-thread:*current-thread*)
           (let ((condition (handler-case (libtmux.control:close-connection connection)
                              (libtmux.control:connection-cleanup-failed (failure) failure))))
             (is (eq connection (libtmux.control:error-connection condition)))
             (is (typep (libtmux:error-cause condition) 'libtmux:cleanup-failed))
             (is (eq condition (aref (libtmux.control:connection-cleanup-failures connection) 0))))
           (let ((pending (libtmux.control:pending-cleanups)))
             (is (find connection pending))
             (fill pending nil)
             (is (find connection (libtmux.control:pending-cleanups))))
           (setf (libtmux.internal::control-peer-worker peer) nil)
           (libtmux.control:close-connection connection)
           (is (not (find connection (libtmux.control:pending-cleanups)))))
      (libtmux.internal::forget-control-peer peer))))

(test control-scope-preserves-primary-exit-if-recording-fails
  (let ((connection (make-instance 'libtmux.control:connection :peer nil)))
    (is (eq :primary
            (catch 'leave
              (libtmux.control::%call-with-connection-scope
               connection (lambda (resource) (declare (ignore resource))
                            (throw 'leave :primary))))))))

(test control-reconnect-validates-before-cutover
  (let* ((client (make-instance 'libtmux:client))
         (connection (local-control-connection
                      :origin-client client :origin-context (slot-value client 'libtmux::context)
                      :origin-generation 0 :origin-session "$0"
                      :origin-witness '(1 1 "socket" "endpoint" "3.8" 1 1 1)))
         (started 0)
         (libtmux.internal::*process-launched-hook* (lambda (job) (declare (ignore job)) (incf started))))
    (unwind-protect
         (progn
           (dolist (options '((:timeout -1) (:request-limit 0) (:event-limit nil)
                              (:event-byte-limit 0) (:reply-byte-limit 0)))
             (signals libtmux:invalid-argument (apply #'libtmux.control:reconnect connection options)))
           (signals libtmux:deadline-exceeded (libtmux.control:reconnect connection :timeout 0))
           (setf (slot-value client 'libtmux::active) (libtmux.internal::make-operation))
           (unwind-protect
                (signals libtmux:client-busy (libtmux.control:reconnect connection))
             (setf (slot-value client 'libtmux::active) nil))
           (setf (slot-value client 'libtmux::generation) 1)
           (let ((condition (handler-case
                                (progn (libtmux.control:reconnect connection) nil)
                              (libtmux.control:connection-stale (failure) failure))))
             (is (typep condition 'libtmux.control:connection-stale))
             (is (eq connection (libtmux.control:error-connection condition)))
             (is (eq connection (libtmux:error-target condition)))
             (is (typep condition 'libtmux:stale-target)))
           (is (eq :ready (libtmux.control:connection-state connection)))
           (is (libtmux:client-open-p client))
           (libtmux:close-client client)
           (signals libtmux:client-closed (libtmux.control:reconnect connection))
           (is (zerop started)))
      (libtmux.control:close-connection connection)
      (libtmux:close-client client))))

(test control-reconnection-scope-binds-both-values-and-closes-original
  (let ((old (local-control-connection))
        (fresh (local-control-connection))
        (other (local-control-connection))
        (snapshot (make-instance 'libtmux:snapshot)))
    (unwind-protect
         (flet ((libtmux.control:reconnect (previous &rest options)
                  (declare (ignore options))
                  (is (eq old previous))
                  (values fresh snapshot)))
           (is (equal '(1 nil :tail)
                      (multiple-value-list
                       (libtmux.control:with-reconnection (resource captured old)
                         (declare (special resource captured))
                         (is (eq fresh (symbol-value 'resource)))
                         (is (eq snapshot (symbol-value 'captured)))
                         (setf resource other captured nil)
                         (values 1 nil :tail)))))
           (is (eq :closed (libtmux.control:connection-state fresh)))
           (is (eq :ready (libtmux.control:connection-state old)))
           (is (eq :ready (libtmux.control:connection-state other))))
      (dolist (connection (list old fresh other)) (libtmux.control:close-connection connection)))))

(test control-reconnection-scope-preserves-primary-failure
  (let* ((primary (make-condition 'simple-error :format-control "body"))
         (secondary (make-condition 'simple-error :format-control "cleanup"))
         (connection (make-instance 'failing-control-close :peer (local-control-peer) :failure secondary)))
    (flet ((libtmux.control:reconnect (previous &rest options)
             (declare (ignore previous options)) (values connection nil)))
      (is (eq primary
              (handler-case
                  (libtmux.control:with-reconnection (resource snapshot nil)
                    (declare (ignore resource snapshot)) (error primary))
                (simple-error (condition) condition))))
      (is (eq secondary (aref (libtmux.control:connection-cleanup-failures connection) 0))))
    (libtmux.internal::close-control-peer (libtmux.control::%peer connection))))
