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
