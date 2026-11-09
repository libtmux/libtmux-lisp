(in-package #:libtmux.tests)

(in-suite control)

(test control-lines-preserve-marker-looking-data-across-chunks
  (let* ((wire (libtmux.internal::encode-utf8
                (format nil "%begin 1 2 1~%~%%end 1 2 1~%raw~Cvalue~%" #\Return)))
         (expected (vector (libtmux.internal::encode-utf8 "%begin 1 2 1")
                           (libtmux.internal::octet-vector #())
                           (libtmux.internal::encode-utf8 "%end 1 2 1")
                           (libtmux.internal::encode-utf8 (format nil "raw~Cvalue" #\Return)))))
    (loop for cut from 0 to (length wire)
          for decoder = (libtmux.internal::make-control-line-decoder)
          for first = (libtmux.internal::feed-control-lines decoder wire :end cut)
          for second = (libtmux.internal::feed-control-lines decoder wire :start cut)
          do (is (equalp expected (concatenate 'vector first second)))
             (is (equalp #() (libtmux.internal::finish-control-lines decoder))))))

(test control-lines-own-partial-input-and-returned-lines
  (let* ((decoder (libtmux.internal::make-control-line-decoder))
         (partial (libtmux.internal::octet-vector #(0 255 13))))
    (is (equalp #() (libtmux.internal::feed-control-lines decoder partial)))
    (fill partial 42)
    (let ((lines (libtmux.internal::feed-control-lines
                  decoder (libtmux.internal::octet-vector #(10 65 10 66)))))
      (is (equalp #(#(0 255 13) #(65)) lines))
      (fill (aref lines 0) 42)
      (setf (aref lines 1) nil)
      (is (equalp #(#(66)) (libtmux.internal::feed-control-lines
                            decoder (libtmux.internal::octet-vector #(10))))))
    (libtmux.internal::finish-control-lines decoder)))

(test control-lines-distinguish-clean-and-truncated-eof
  (let ((decoder (libtmux.internal::make-control-line-decoder)))
    (is (equalp #() (libtmux.internal::finish-control-lines decoder)))
    (signals libtmux:invalid-argument
      (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #())))
    (signals libtmux:invalid-argument
      (libtmux.internal::finish-control-lines decoder)))
  (let ((decoder (libtmux.internal::make-control-line-decoder)))
    (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #(65)))
    (signals libtmux:decoding-error (libtmux.internal::finish-control-lines decoder))
    (signals libtmux:invalid-argument
      (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #(10))))))

(test control-lines-enforce-retained-and-per-feed-limits
  (let ((decoder (libtmux.internal::make-control-line-decoder
                  :line-byte-limit 3 :batch-byte-limit 8 :batch-line-limit 2)))
    (is (equalp #(#(65 66 67) #(68 69 70))
                (libtmux.internal::feed-control-lines
                 decoder (libtmux.internal::octet-vector #(65 66 67 10 68 69 70 10)))))
    (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #(65 66 67)))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #(68))))
    (signals libtmux:invalid-argument (libtmux.internal::finish-control-lines decoder)))
  (dolist (limits '((:batch-byte-limit 2) (:batch-line-limit 1)))
    (let ((decoder (apply #'libtmux.internal::make-control-line-decoder limits)))
      (signals libtmux:output-limit-exceeded
        (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #(65 10 66 10))))
      (signals libtmux:invalid-argument (libtmux.internal::finish-control-lines decoder)))))

(test control-lines-reject-bad-arguments-without-consuming-input
  (signals libtmux:invalid-argument
    (libtmux.internal::make-control-line-decoder :line-byte-limit 0))
  (let ((decoder (libtmux.internal::make-control-line-decoder))
        (wire (libtmux.internal::octet-vector #(65 10))))
    (signals libtmux:invalid-argument
      (libtmux.internal::feed-control-lines decoder wire :start 3))
    (signals libtmux:invalid-argument
      (libtmux.internal::feed-control-lines decoder "A"))
    (is (equalp #(#(65)) (libtmux.internal::feed-control-lines decoder wire)))))

(test control-lines-poison-on-cancellation-and-nonlocal-exit
  (let* ((checks 0)
         (decoder (libtmux.internal::make-control-line-decoder
                   :check-budget (lambda ()
                                   (when (> (incf checks) 1)
                                     (error 'libtmux:command-cancelled))))))
    (signals libtmux:command-cancelled
      (libtmux.internal::feed-control-lines
       decoder (make-array 300 :element-type '(unsigned-byte 8) :initial-element 65)))
    (signals libtmux:invalid-argument (libtmux.internal::finish-control-lines decoder)))
  (let ((decoder (libtmux.internal::make-control-line-decoder
                  :check-budget (lambda () (throw 'stop :cancelled)))))
    (is (eq :cancelled
            (catch 'stop
              (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #(65))))))
    (signals libtmux:invalid-argument (libtmux.internal::finish-control-lines decoder))))

(test control-lines-reject-budget-callback-reentry-during-feed-and-eof
  (dolist (operation '(:feed :finish))
    (let ((decoder nil) (attempted nil))
      (setf decoder
            (libtmux.internal::make-control-line-decoder
             :check-budget
             (lambda ()
               (unless attempted
                 (setf attempted t)
                 (libtmux.internal::feed-control-lines
                  decoder (libtmux.internal::octet-vector #()))))))
      (signals libtmux:invalid-argument
        (ecase operation
          (:feed (libtmux.internal::feed-control-lines
                  decoder (libtmux.internal::octet-vector #())))
          (:finish (libtmux.internal::finish-control-lines decoder))))
      (is (eq t attempted))
      (signals libtmux:invalid-argument (libtmux.internal::finish-control-lines decoder)))))

(test control-pane-output-preserves-every-byte-and-owns-the-result
  (let* ((header (libtmux.internal::encode-utf8 "%output %4294967295 "))
         (wire (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (map nil (lambda (byte) (vector-push-extend byte wire)) header)
    (dotimes (byte 256)
      (if (or (< byte 32) (= byte 92))
          (map nil (lambda (char) (vector-push-extend (char-code char) wire))
               (format nil "~C~3,'0O" #\\ byte))
          (vector-push-extend byte wire)))
    (multiple-value-bind (output pane age extended-p)
        (libtmux.internal::decode-control-output-line wire)
      (fill wire 0)
      (is (equalp (coerce (loop for byte below 256 collect byte) 'vector) output))
      (is (string= "%4294967295" pane))
      (is (null age))
      (is (null extended-p)))))

(test control-pane-output-understands-extended-reserved-fields-and-empty-data
  (multiple-value-bind (output pane age extended-p)
      (libtmux.internal::decode-control-output-line
       (libtmux.internal::encode-utf8 "%extended-output %0 18446744073709551615 future :token : "))
    (is (equalp #() output))
    (is (string= "%0" pane))
    (is (= 18446744073709551615 age))
    (is (eq t extended-p)))
  (is (equalp #(37 101 110 100 32 49 32 50 32 49)
              (libtmux.internal::decode-control-output-line
               (libtmux.internal::encode-utf8 "%output %1 %end 1 2 1")))))

(test control-pane-output-rejects-broken-headers-and-escapes
  (dolist (text (list "%output %1" "%output %01 x" "%output %-1 x"
                      "%output %4294967296 x"
                      "%extended-output %1 18446744073709551616 : x"
                      "%extended-output %1 00 : x"
                      "%extended-output %1 -1 : x" "%extended-output %1 0 :"
                      (format nil "%output %1 ~C12" #\\)
                      (format nil "%output %1 ~C400" #\\)
                      (format nil "%output %1 ~Cx00" #\\)
                      (format nil "%output %1 raw~Cnewline" #\Newline)))
    (signals libtmux:decoding-error
      (libtmux.internal::decode-control-output-line (libtmux.internal::encode-utf8 text))))
  (is (equalp #(120 32 101 120 116 114 97)
              (libtmux.internal::decode-control-output-line
               (libtmux.internal::encode-utf8 "%output %1 x extra")))))

(test control-pane-output-bounds-decoding-and-checks-cancellation
  (let ((wire (libtmux.internal::encode-utf8 (format nil "%output %1 ~C000x" #\\))))
    (is (equalp #(0 120) (libtmux.internal::decode-control-output-line wire :byte-limit 2)))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-control-output-line wire :byte-limit 1))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-control-output-line wire :line-byte-limit 4))
    (signals libtmux:command-cancelled
      (libtmux.internal::decode-control-output-line
       wire :check-budget (lambda () (error 'libtmux:command-cancelled))))))

(test control-codecs-snapshot-input-before-budget-callbacks
  (let* ((wire (libtmux.internal::octet-vector #(65 10)))
         (decoder (libtmux.internal::make-control-line-decoder
                   :check-budget (lambda () (fill wire 42)))))
    (is (equalp #(#(65)) (libtmux.internal::feed-control-lines decoder wire))))
  (let ((wire (libtmux.internal::encode-utf8 "%output %1 X")))
    (is (equalp #(88)
                (libtmux.internal::decode-control-output-line
                 wire :check-budget (lambda () (fill wire 42)))))))
