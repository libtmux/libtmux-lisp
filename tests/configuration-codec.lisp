(in-package #:libtmux.tests)

(in-suite unit)

(test configuration-values-decode-as-inert-owned-text
  (dolist (entry
           (list (list "''" "")
                 (list "plain" "plain")
                 (list (format nil "'a\"b~Cnc'" #\\) (format nil "a\"b~%c"))
                 (list (format nil "\" ~C$HOME;#{pid}\"" #\\) " $HOME;#{pid}")
                 (list (format nil "~C~~" #\\) "~")
                 (list (format nil "\"~C~Cn~Ct~C101\"" #\\ #\\ #\\ #\\)
                       (format nil "~Cn~CA" #\\ #\Tab))
                 (list "\"λ 雪\"" "λ 雪")))
    (let* ((bytes (libtmux.internal::encode-utf8 (first entry)))
           (value (libtmux.internal::decode-argument-token bytes)))
      (fill bytes 0)
      (is (string= (second entry) value)))))

(test configuration-values-reject-malformed-and-bounded-input
  (signals libtmux:invalid-argument
    (libtmux.internal::decode-argument-token 42))
  (dolist (text (list "" "'" "\"" "'unterminated" "\"x\" \"y\"" "two words"
                      (format nil "bad~C" #\\)
                      (format nil "~Cx41" #\\)
                      (format nil "~C12" #\\)
                      (format nil "~C400" #\\)
                      (format nil "~C000" #\\)
                      (format nil "~C377" #\\)))
    (signals libtmux:decoding-error
      (libtmux.internal::decode-argument-token (libtmux.internal::encode-utf8 text))))
  (signals libtmux:decoding-error
    (libtmux.internal::decode-argument-token (libtmux.internal::octet-vector #(0))))
  (signals libtmux:output-limit-exceeded
    (libtmux.internal::decode-argument-token (libtmux.internal::encode-utf8 "value") :byte-limit 4))
  (signals libtmux:deadline-exceeded
    (libtmux.internal::decode-argument-token
     (libtmux.internal::encode-utf8 "value")
     :check-budget (lambda () (error 'libtmux:deadline-exceeded :message "Fixture deadline")))))

(test configuration-values-check-cancellation-after-conversion
  (let ((original (symbol-function 'libtmux.internal::strict-text))
        (cancelled nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'libtmux.internal::strict-text)
                 (lambda (octets)
                   (prog1 (funcall original octets) (setf cancelled t))))
           (signals libtmux:command-cancelled
             (libtmux.internal::decode-argument-token
              (libtmux.internal::encode-utf8 "value")
              :check-budget (lambda ()
                              (when cancelled
                                (error 'libtmux:command-cancelled))))))
      (setf (symbol-function 'libtmux.internal::strict-text) original))))

(defun configuration-prefix-frame (timestamp number payload)
  (format nil "%begin ~D ~D 0~%~A%end ~D ~D 0~%" timestamp number payload timestamp number))

(test configuration-prefix-leaves-schema-and-delimiter-looking-data-untouched
  (let* ((prefix (concatenate 'string
                  (configuration-prefix-frame 20 9 "")
                  (configuration-prefix-frame 21 42 "")
                  (configuration-prefix-frame 23 99 (format nil "nonce:leaf~%"))
                  (format nil "%begin 24 1 0~%")))
         (bytes (libtmux.internal::encode-utf8
                  (concatenate 'string prefix (format nil "VALUE=\"line~%%end 24 1 0~%still data\"~%")))))
    (is (equal (list :leaf (length prefix) 24 1)
               (multiple-value-list
                 (libtmux.internal::decode-configuration-prefix bytes "nonce" 1))))))

(test configuration-prefix-recognizes-refusal-before-later-guards
  (let* ((prefix (concatenate 'string
                  (configuration-prefix-frame 30 8 "")
                  (configuration-prefix-frame 31 44 "")
                  (configuration-prefix-frame 32 90 (format nil "nonce:target~%"))))
         (bytes (libtmux.internal::encode-utf8 (concatenate 'string prefix "opaque tail"))))
    (is (equal (list :target-refused (length prefix) 32 90)
               (multiple-value-list
                 (libtmux.internal::decode-configuration-prefix bytes "nonce" 3))))))

(test configuration-prefix-validates-native-numbers-and-absolute-offsets
  (let* ((marker (configuration-prefix-frame -1 0 (format nil "nonce:leaf~%")))
         (leaf (format nil "%begin 9223372036854775807 0 0~%"))
         (prefix (concatenate 'string
                   (configuration-prefix-frame -9223372036854775808 4294967295 "") marker leaf))
         (bytes (libtmux.internal::encode-utf8 (concatenate 'string "unused" prefix "opaque"))))
    (is (equal (list :leaf (+ 6 (length prefix)) 9223372036854775807 0)
               (multiple-value-list
                 (libtmux.internal::decode-configuration-prefix bytes "nonce" 0 :start 6))))
    (dolist (pair '(("00" "1") ("-0" "1") ("+1" "1")
                    ("9223372036854775808" "1") ("-9223372036854775809" "1")
                    ("1" "01") ("1" "-1") ("1" "+1") ("1" "4294967296")))
      (let ((wire (libtmux.internal::encode-utf8
                    (concatenate 'string
                      (format nil "%begin ~A ~A 0~%%end ~A ~A 0~%"
                              (first pair) (second pair) (first pair) (second pair))
                      marker leaf))))
        (signals libtmux:decoding-error
          (libtmux.internal::decode-configuration-prefix wire "nonce" 0))))))

(test configuration-prefix-rejects-foreign-and-misplaced-frames
  (let* ((guard (configuration-prefix-frame 1 1 ""))
         (leaf (format nil "%begin 2 44 0~%"))
         (marker (configuration-prefix-frame 1 23 (format nil "nonce:leaf~%")))
         (valid (concatenate 'string guard marker leaf)))
    (dolist (case
             (list (list (concatenate 'string (format nil "%session-changed foreign~%") valid) 0)
                   (list (concatenate 'string (format nil "~CP1000p" #\Esc) valid) 0)
                   (list (concatenate 'string (format nil "%begin 1 1 1~%%end 1 1 1~%") marker leaf) 0)
                   (list (concatenate 'string (format nil "%begin 1 1 0~%%error 1 1 0~%") marker leaf) 0)
                   (list (concatenate 'string (format nil "%begin 1 1 0~%%end 1 2 0~%") marker leaf) 0)
                   (list (concatenate 'string (configuration-prefix-frame 1 1 (format nil "foreign~%")) valid) 0)
                   (list (concatenate 'string guard guard marker leaf) 0)
                   (list valid 1)
                   (list (concatenate 'string guard
                           (configuration-prefix-frame 1 23 (format nil "wrong:leaf~%")) leaf) 0)
                   (list (concatenate 'string guard
                           (configuration-prefix-frame 1 23 (format nil "nonce:target~%"))) 0)
                   (list (concatenate 'string guard guard
                           (configuration-prefix-frame 1 23 (format nil "nonce:server~%"))) 1)
                   (list (concatenate 'string guard
                           (configuration-prefix-frame 1 23 (format nil "nonce:leaf ~%")) leaf) 0)
                   (list (concatenate 'string (format nil "%begin 1 1 0~C~%" #\Return) valid) 0)))
      (signals libtmux:decoding-error
        (libtmux.internal::decode-configuration-prefix
         (libtmux.internal::encode-utf8 (first case)) "nonce" (second case))))
    (dolist (end (list 0 1 (1- (length valid))))
      (signals libtmux:decoding-error
        (libtmux.internal::decode-configuration-prefix
         (libtmux.internal::encode-utf8 valid) "nonce" 0 :end end)))))

(test configuration-prefix-shares-budgets-and-preserves-cancellation
  (let* ((wire (libtmux.internal::encode-utf8
                 (concatenate 'string (configuration-prefix-frame 1 1 "")
                   (configuration-prefix-frame 1 23 (format nil "nonce:server~%")))))
         (budget (libtmux.internal::make-configuration-decode-budget
                  :remaining-bytes (* 2 (length wire)) :remaining-frames 4)))
    (dotimes (index 2)
      (declare (ignore index))
      (is (eq :server-refused
              (libtmux.internal::decode-configuration-prefix wire "nonce" 0 :budget budget))))
    (is (zerop (libtmux.internal::configuration-decode-budget-remaining-bytes budget)))
    (is (zerop (libtmux.internal::configuration-decode-budget-remaining-frames budget)))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-configuration-prefix wire "nonce" 0 :budget budget))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-configuration-prefix wire "nonce" 0
        :budget (libtmux.internal::make-configuration-decode-budget :remaining-bytes (1- (length wire)))))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-configuration-prefix wire "nonce" 0
        :budget (libtmux.internal::make-configuration-decode-budget :remaining-frames 1)))
    (setf budget (libtmux.internal::make-configuration-decode-budget :remaining-bytes (length wire)))
    (setf (libtmux.internal::configuration-decode-budget-check budget)
          (lambda ()
            (when (zerop (libtmux.internal::configuration-decode-budget-remaining-bytes budget))
              (error 'libtmux:command-cancelled :message "Fixture cancellation at parser return"))))
    (signals libtmux:command-cancelled
      (libtmux.internal::decode-configuration-prefix wire "nonce" 0 :budget budget))
    (signals libtmux:invalid-argument (libtmux.internal::decode-configuration-prefix 42 "nonce" 0))
    (signals libtmux:invalid-argument (libtmux.internal::decode-configuration-prefix wire "bad:nonce" 0))
    (signals libtmux:invalid-argument (libtmux.internal::decode-configuration-prefix wire "nonce" -1))))
