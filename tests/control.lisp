(in-package #:libtmux.tests)

(in-suite control)

(defun local-control-connection (&rest options)
  (libtmux.control::%connection-for-peer (apply #'local-control-peer options)))

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
