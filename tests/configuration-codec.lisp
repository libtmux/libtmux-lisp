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

(test configuration-environment-leaf-consumes-schema-before-terminator
  (let* ((value (format nil "first~%%end 42 10 0~%last"))
         (body (format nil "APP=\"~A\"; export APP;~%%end 42 10 0~%" value))
         (wire (libtmux.internal::encode-utf8 (concatenate 'string body "opaque hook tail"))))
    (is (equal (list :present value (length body) :end)
               (multiple-value-list
                 (libtmux.internal::decode-configuration-environment-leaf
                  wire (libtmux.internal::encode-utf8 "APP") 42 10 :profile :direct))))))

(test configuration-environment-leaf-refuses-indistinguishable-success
  (let* ((begin (format nil "%begin 42 10 0~%"))
         (close (format nil "%end 42 10 0~%"))
         (hook-begin (format nil "%begin 42 20 0~%"))
         (hook-close (format nil "%end 42 20 0~%"))
         (name (concatenate 'string close hook-begin "X"))
         (body (format nil "~A=\"value\"; export ~A;~%" name name))
         (residual (subseq body (+ (length close) (length hook-begin))))
         (present (concatenate 'string begin body close hook-begin hook-close (format nil "%exit~%")))
         (empty (concatenate 'string begin close hook-begin residual close hook-begin hook-close
                             (format nil "%exit~%"))))
    (is (string= present empty))
    (let ((condition
            (handler-case
                (libtmux.internal::decode-configuration-environment-leaf
                 (libtmux.internal::encode-utf8 present) (libtmux.internal::encode-utf8 name)
                 42 10 :start (length begin) :profile :direct)
              (libtmux:decoding-error (condition) condition))))
      (is (eq 'libtmux.internal::ambiguous-environment-frame (type-of condition))))))

(test configuration-environment-leaf-accepts-a-distinct-observed-tuple
  (let* ((name (format nil "%end 42 10 0~%%begin 42 20 0~%X"))
         (close (format nil "%end 43 0 0~%"))
         (body (format nil "~A=\"value\"; export ~A;~%~A" name name close)))
    (is (equal (list :present "value" (length body) :end)
               (multiple-value-list
                 (libtmux.internal::decode-configuration-environment-leaf
                  (libtmux.internal::encode-utf8 body) (libtmux.internal::encode-utf8 name)
                  43 0 :profile :direct))))
    (is (equal (list :empty nil (length close) :end)
               (multiple-value-list
                 (libtmux.internal::decode-configuration-environment-leaf
                  (libtmux.internal::encode-utf8 (concatenate 'string close "opaque hook tail"))
                  (libtmux.internal::encode-utf8 name) 43 0 :profile :direct))))))

(defun configuration-environment-value-wire (quoted)
  (concatenate '(vector (unsigned-byte 8))
               (libtmux.internal::encode-utf8 "APP=")
               (libtmux.internal::octet-vector quoted)
               (libtmux.internal::encode-utf8 (format nil "; export APP;~%%end 7 9 0~%"))))

(test configuration-environment-escapes-follow-the-source-profile
  (let ((all '(:direct :vis-noslash :vis-noslash-dollar)))
    (dolist (case
             (list (list all #(34 34) "")
                   (list all #(34 111 102 102 34) "off")
                   (list all #(34 92 34 92 92 92 36 92 96 34)
                         (coerce (list #\" #\\ #\$ #\`) 'string))
                   (list all #(34 92 92 110 34) (coerce (list #\\ #\n) 'string))
                   (list '(:direct) #(34 10 9 13 7 8 11 12 1 127 34)
                         (map 'string #'code-char #(10 9 13 7 8 11 12 1 127)))
                   (list '(:vis-noslash :vis-noslash-dollar)
                         #(34 10 9 92 114 92 97 92 98 92 118 92 102 92 48 48 49 92 49 55 55 34)
                         (map 'string #'code-char #(10 9 13 7 8 11 12 1 127)))
                   (list all #(34 233 155 170 206 187 34) "雪λ")
                   (list '(:direct :vis-noslash) #(34 92 36 65 34) "$A")
                   (list '(:vis-noslash-dollar) #(34 92 92 36 65 34) "$A")
                   (list all #(34 92 36 49 34) "$1")
                   (list '(:vis-noslash-dollar) #(34 92 92 92 92 36 65 34)
                         (concatenate 'string (string #\\) "$A"))
                   (list all #(34 92 92 92 36 49 34) (concatenate 'string (string #\\) "$1"))))
      (dolist (profile (first case))
        (let* ((wire (configuration-environment-value-wire (second case)))
               (original (copy-seq wire)))
          (multiple-value-bind (state value offset terminal)
              (libtmux.internal::decode-configuration-environment-leaf
               wire (libtmux.internal::encode-utf8 "APP") 7 9 :profile profile)
            (is (equal (list :present (third case) (length wire) :end)
                       (list state value offset terminal)))
            (fill value #\Z)
            (is (equalp original wire))))))))

(test configuration-environment-rejects-non-emitted-escapes
  (dolist (profile '(:direct :vis-noslash :vis-noslash-dollar))
    (dolist (quoted '(#(34 92 110 34) #(34 92 116 34) #(34 92 115 34)
                      #(34 92 48 48 48 34) #(34 92 49 48 49 34)
                      #(34 92 51 48 51 92 50 53 49 34) #(34 36 65 34) #(34 96 34)
                      #(34 0 34) #(34 255 34)))
      (signals libtmux:decoding-error
        (libtmux.internal::decode-configuration-environment-leaf
         (configuration-environment-value-wire quoted) (libtmux.internal::encode-utf8 "APP")
         7 9 :profile profile))))
  (dolist (profile '(:vis-noslash :vis-noslash-dollar))
    (dolist (quoted '(#(34 13 34) #(34 7 34) #(34 92 48 49 53 34)))
      (signals libtmux:decoding-error
        (libtmux.internal::decode-configuration-environment-leaf
         (configuration-environment-value-wire quoted) (libtmux.internal::encode-utf8 "APP")
         7 9 :profile profile))))
  (dolist (quoted '(#(34 92 36 65 34) #(34 92 92 36 49 34) #(34 92 92 92 36 65 34)))
    (signals libtmux:decoding-error
      (libtmux.internal::decode-configuration-environment-leaf
       (configuration-environment-value-wire quoted) (libtmux.internal::encode-utf8 "APP")
       7 9 :profile :vis-noslash-dollar))))

(test configuration-environment-states-use-exact-native-schemas
  (dolist (name (list "APP" "unset X" "unknown variable: X"))
    (let ((body (format nil "~A=\"value\"; export ~A;~%%end 7 9 0~%" name name)))
      (is (eq :present
              (libtmux.internal::decode-configuration-environment-leaf
               (libtmux.internal::encode-utf8 body) (libtmux.internal::encode-utf8 name) 7 9)))))
  (dolist (case (list (list :removed (format nil "unset APP;~%%end 7 9 0~%") :end)
                     (list :missing (format nil "unknown variable: APP~%%error 7 9 0~%") :error)
                     (list :empty (format nil "%end 7 9 0~%") :end)))
    (let* ((body (second case))
           (wire (concatenate '(vector (unsigned-byte 8)) (libtmux.internal::encode-utf8 body) #(255 0))))
      (is (equal (list (first case) nil (length body) (third case))
                 (multiple-value-list
                   (libtmux.internal::decode-configuration-environment-leaf
                    wire (libtmux.internal::encode-utf8 "APP") 7 9))))))
  (let* ((name (format nil "RAW$A~%%error 7 9 0~%"))
         (body (format nil "unknown variable: ~A~%%error 7 9 0~%" name)))
    (is (equal (list :missing nil (length body) :error)
               (multiple-value-list
                 (libtmux.internal::decode-configuration-environment-leaf
                  (libtmux.internal::encode-utf8 body) (libtmux.internal::encode-utf8 name)
                  7 9 :profile :vis-noslash-dollar)))))
  (dolist (body (list (format nil "APP=\"value\"; export OTHER;~%%end 7 9 0~%")
                     (format nil "APP=\"value\"; export APP;~%%error 7 9 0~%")
                     (format nil "unknown variable: APP~%%end 7 9 0~%")
                     (format nil "unknown variable: OTHER~%%error 7 9 0~%")
                     (format nil "unset APP;~%%end 7 8 0~%")))
    (signals libtmux:decoding-error
      (libtmux.internal::decode-configuration-environment-leaf
       (libtmux.internal::encode-utf8 body) (libtmux.internal::encode-utf8 "APP") 7 9))))

(test configuration-environment-budgets-count-octets-without-a-second-begin
  (let* ((wire (configuration-environment-value-wire #(34 233 155 170 34)))
         (name (libtmux.internal::encode-utf8 "APP"))
         (budget (libtmux.internal::make-configuration-decode-budget
                  :remaining-bytes (length wire) :remaining-frames 0)))
    (is (eq :present (libtmux.internal::decode-configuration-environment-leaf
                     wire name 7 9 :value-limit 3 :budget budget)))
    (is (zerop (libtmux.internal::configuration-decode-budget-remaining-bytes budget)))
    (is (zerop (libtmux.internal::configuration-decode-budget-remaining-frames budget)))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-configuration-environment-leaf wire name 7 9 :value-limit 2))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-configuration-environment-leaf wire name 7 9 :budget budget))
    (is (string= "" (nth-value 1
                     (libtmux.internal::decode-configuration-environment-leaf
                      (configuration-environment-value-wire #(34 34)) name 7 9 :value-limit 0))))
    (let ((original (symbol-function 'libtmux.internal::strict-text))
          (cancelled nil) (failure (make-condition 'libtmux:command-cancelled)))
      (unwind-protect
           (progn
             (setf (symbol-function 'libtmux.internal::strict-text)
                   (lambda (bytes)
                     (prog1 (funcall original bytes)
                       (when (equalp bytes #(233 155 170)) (setf cancelled t)))))
             (let ((caught
                     (handler-case
                         (libtmux.internal::decode-configuration-environment-leaf
                          wire name 7 9 :budget (libtmux.internal::make-configuration-decode-budget
                                                :check (lambda () (when cancelled (error failure)))))
                       (libtmux:command-cancelled (condition) condition))))
               (is (eq failure caught))))
        (setf (symbol-function 'libtmux.internal::strict-text) original)))))

(test configuration-environment-owns-names-results-and-checks-forward-work
  (let* ((name (libtmux.internal::encode-utf8 "APP"))
         (wire (configuration-environment-value-wire #(34 118 97 108 117 101 34)))
         (budget (libtmux.internal::make-configuration-decode-budget :check (lambda () (fill name 0))))
         (first (nth-value 1 (libtmux.internal::decode-configuration-environment-leaf
                              wire name 7 9 :budget budget)))
         (second (nth-value 1 (libtmux.internal::decode-configuration-environment-leaf
                               wire (libtmux.internal::encode-utf8 "APP") 7 9))))
    (is (string= first second))
    (fill first #\Z)
    (is (string= "value" second)))
  (let* ((name (make-string 513 :initial-element (code-char 1)))
         (printed (with-output-to-string (stream)
                    (dotimes (index (length name))
                      (declare (ignorable index))
                      (write-char #\\ stream)
                      (write-string "001" stream))))
         (wire (libtmux.internal::encode-utf8
                 (format nil "~A=\"value\"; export ~A;~%%end 7 9 0~%" printed printed)))
         (original (symbol-function 'libtmux.internal::visit-configuration-environment-name))
         (emitted 0) (failure (make-condition 'libtmux:deadline-exceeded)))
    (unwind-protect
         (progn
           (setf (symbol-function 'libtmux.internal::visit-configuration-environment-name)
                 (lambda (name profile emit check)
                   (funcall original name profile
                            (lambda (byte) (incf emitted) (funcall emit byte)) check)))
           (let ((caught
                   (handler-case
                       (libtmux.internal::decode-configuration-environment-leaf
                        wire (libtmux.internal::encode-utf8 name) 7 9 :profile :vis-noslash
                        :budget (libtmux.internal::make-configuration-decode-budget
                                 :check (lambda () (when (>= emitted 300) (error failure)))))
                     (libtmux:deadline-exceeded (condition) condition))))
             (is (eq failure caught))
             (is (< 0 emitted (length printed)))))
      (setf (symbol-function 'libtmux.internal::visit-configuration-environment-name) original))))
