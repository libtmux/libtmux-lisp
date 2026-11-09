(in-package #:libtmux.tests)
(in-suite unit)

(test configuration-read-names-are-bounded-owned-data
  (let* ((name (copy-seq "@one"))
         (input (vector name "@two"))
         (owned (libtmux.internal::owned-configuration-names input)))
    (setf (char name 1) #\X (aref input 1) "changed")
    (is (equalp #("@one" "@two") owned)))
  (let ((first (libtmux.internal::owned-configuration-names nil))
        (second (libtmux.internal::owned-configuration-names #())))
    (is (typep first 'simple-vector))
    (is (zerop (length first)))
    (is (not (eq first second))))
  (dolist (bad (list "name" '("name" . :tail) '(nil) '("") '("status-format[0]")
                    (make-array 4097 :initial-element "@one")))
    (signals libtmux:invalid-argument (libtmux.internal::owned-configuration-names bad)))
  (let ((cycle (list "@one")))
    (setf (cdr cycle) cycle)
    (signals libtmux:invalid-argument (libtmux.internal::owned-configuration-names cycle)))
  (is (equalp (vector (format nil "%end 0 0 0~%NAME"))
              (libtmux.internal::owned-configuration-names
               (list (format nil "%end 0 0 0~%NAME")) :environment t)))
  (signals libtmux:invalid-argument
    (libtmux.internal::owned-configuration-names '("BAD=NAME") :environment t)))

(test ordinary-option-adapter-preserves-false-empty-and-whole-payload
  (let ((catalog (libtmux.internal::configuration-catalog "3.3a")))
    (is (equal '(:present nil)
               (multiple-value-list
                (libtmux.internal::decode-ordinary-option
                 (libtmux.internal::encode-utf8 (format nil "renumber-windows off~%"))
                 catalog "renumber-windows" :session))))
    (is (equal '(:absent nil)
               (multiple-value-list
                (libtmux.internal::decode-ordinary-option #() catalog "renumber-windows" :session))))
    (is (equalp '(:present #(("7" . "")))
                (multiple-value-list
                 (libtmux.internal::decode-ordinary-option
                  (libtmux.internal::encode-utf8 (format nil "status-format[7] ''~%"))
                  catalog "status-format" :session))))
    (signals libtmux:decoding-error
      (libtmux.internal::decode-ordinary-option
       (libtmux.internal::encode-utf8 (format nil "renumber-windows off~%extra~%"))
       catalog "renumber-windows" :session))))

(test ordinary-environment-adapter-owns-framing-and-record-budget
  (let* ((name (format nil "%end 0 0 0~%NAME"))
         (value (format nil "value~%%end 1 0 0~%tail"))
         (body (libtmux.internal::encode-utf8 (format nil "~A=\"~A\"; export ~A;~%" name value name)))
         (budget (libtmux.internal::make-configuration-decode-budget :remaining-records 2)))
    (is (equal (list :present value)
               (multiple-value-list
                (libtmux.internal::decode-ordinary-environment body name :budget budget))))
    (is (equal '(:empty nil)
               (multiple-value-list
                (libtmux.internal::decode-ordinary-environment #() name :budget budget))))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-ordinary-environment #() name :budget budget)))
  (is (equal '(:missing nil)
             (multiple-value-list
              (libtmux.internal::decode-ordinary-environment
               (libtmux.internal::encode-utf8 (format nil "unknown variable: MISSING~%")) "MISSING" :failed t)))))

(test empty-configuration-requests-do-no-io
  (let ((client (make-instance 'libtmux:client)))
    (multiple-value-bind (records outcomes) (libtmux:show-options client :scope :global-session :names nil)
      (is (typep records 'simple-vector)) (is (zerop (length records)))
      (is (typep outcomes 'simple-vector)) (is (zerop (length outcomes)))
      (is (not (eq records (libtmux:show-options client :scope :global-session :names #())))))
    (is (zerop (length (libtmux:show-hooks client :scope :global-session :names nil))))
    (is (zerop (length (libtmux:show-environment client :scope :global :names nil))))
    (dolist (reader (list (lambda () (libtmux:show-options client :scope :global-session :names nil))
                         (lambda () (libtmux:show-hooks client :scope :global-session :names nil))
                         (lambda () (libtmux:show-environment client :scope :global :names nil))))
      (is (= 2 (length (multiple-value-list (funcall reader))))))
    (signals libtmux:invalid-argument (libtmux:show-environment client :scope :global))
    (signals libtmux:invalid-argument (libtmux:show-options client :scope :session :names nil))
    (signals type-error (libtmux:show-options client :scope :global-session :names nil :cancel-token :invalid))
    (signals libtmux:invalid-argument (libtmux:show-hooks client :scope :server :names nil))))
