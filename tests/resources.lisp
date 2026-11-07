(in-package #:libtmux.tests)

(in-suite unit)

(test outcome-value-owns-returned-data
  (let* ((outcome (make-instance 'libtmux:command-outcome
                                 :value (vector (list (copy-seq "retained"))) :present-p t))
         (first (libtmux:outcome-value outcome)))
    (setf (char (first (aref first 0)) 0) #\X
          (aref first 0) nil)
    (multiple-value-bind (value present-p) (libtmux:outcome-value outcome)
      (is (eq t present-p))
      (is (equalp #(("retained")) value)))))

(defclass bad-close-client (libtmux:client) ())
(defmethod libtmux:close-client ((client bad-close-client))
  (call-next-method)
  (error "cleanup failed"))

(test resource-scope-values-and-exits
  (let ((original (make-instance 'libtmux:client))
        (replacement (make-instance 'libtmux:client)))
    (flet ((libtmux:open-client () original))
      (is (equal '(1 nil :tail)
                 (multiple-value-list
                  (libtmux:with-client (client)
                    (setf client replacement)
                    (values 1 nil :tail))))))
    (is (not (libtmux:client-open-p original)))
    (is (libtmux:client-open-p replacement))
    (libtmux:close-client replacement))
  (let ((client (make-instance 'bad-close-client)))
    (flet ((libtmux:open-client () client))
      (is (eq :preserved
              (catch 'leave
                (libtmux:with-client (owned)
                  (declare (ignore owned))
                  (throw 'leave :preserved)))))
      (is (= 1 (length (libtmux:client-cleanup-failures client))))
      (signals simple-error
        (libtmux:with-client (owned) (declare (ignore owned)) :normal))))
  (let ((client (make-instance 'bad-close-client)))
    (flet ((libtmux:open-client () client))
      (is (equal "primary"
                 (handler-case
                     (libtmux:with-client (owned)
                       (declare (ignore owned)) (error "primary"))
                   (simple-error (condition) (princ-to-string condition)))))
      (is (= 1 (length (libtmux:client-cleanup-failures client)))))))

(test supported-version-floor
  (signals libtmux:unsupported-tmux (libtmux.internal::supported-version "3.3"))
  (signals libtmux:unsupported-tmux (libtmux.internal::supported-version "3.2a"))
  (signals libtmux:unsupported-tmux (libtmux.internal::supported-version "next-3.8"))
  (dolist (version '("3.3a" "3.4" "3.5" "3.5a" "3.6" "3.6a" "3.6b"
                     "3.7" "3.7a" "3.7b" "3.7c" "3.8"))
    (is (equal version (libtmux.internal::supported-version version)))))

(test cancellation-without-resource-allocation
  (let ((token (libtmux:make-cancellation-token)))
    (is (not (libtmux:cancelled-p token)))
    (is (libtmux:cancel token))
    (is (not (libtmux:cancel token)))
    (is (libtmux:cancelled-p token))
    (is (null (slot-value token 'libtmux::registrations)))))

(test finite-argument-validation
  (let ((cycle (list "arg")))
    (setf (cdr cycle) cycle)
    (signals libtmux:invalid-argument (libtmux.internal::argument-vector cycle)))
  (signals libtmux:invalid-argument (libtmux.internal::argument-vector '("a" . "b")))
  (signals libtmux:invalid-argument (libtmux.internal::argument-vector '("a" 1)))
  (signals libtmux:invalid-argument (libtmux.internal::octet-vector #(0 256)))
  (signals libtmux:invalid-argument (libtmux.internal::check-limits -1 100)))
