(in-package #:libtmux.tests)

(def-suite configuration-option-leaves :in unit)
(in-suite configuration-option-leaves)

(defun option-leaf-wire (body &optional (terminal :end))
  (libtmux.internal::encode-utf8
   (format nil "~A%~(~A~) 7 9 0~%" body terminal)))

(defun decode-option-test-leaf (version name scope body &rest options)
  (apply #'libtmux.internal::decode-configuration-option-leaf
         (option-leaf-wire body)
         (libtmux.internal::configuration-catalog version) name scope 7 9 options))

(defun formatted-option-row (name key flags value)
  (format nil "libtmux-option/1~C~A~C~A~C~{~D~C~}~A~%"
          #\Tab name #\Tab key #\Tab
          (loop for flag in flags append (list flag #\Tab)) value))

(test option-leaves-decode-typed-scalars-and-preserve-false
  (dolist (case '(("renumber-windows" :global-session "off" nil)
                  ("status" :global-session "off" "off")
                  ("history-limit" :global-session "2000" 2000)
                  ("mode-keys" :global-window "vi" "vi")
                  ("prefix" :global-session "C-b" "C-b")
                  ("display-panes-colour" :global-session "blue" "blue")
                  ("@user" :global-session "''" "")))
    (destructuring-bind (name scope printed expected) case
      (multiple-value-bind (state value offset terminal)
          (decode-option-test-leaf "3.3a" name scope (format nil "~A ~A~%" name printed))
        (is (eq state :present))
        (is (equal value expected))
        (is (plusp offset))
        (is (eq terminal :end)))))
  (is (equal '(:present "")
             (subseq (multiple-value-list
                      (decode-option-test-leaf "3.6" "default-client-command" :server
                                              (format nil "default-client-command ~%"))) 0 2))))

(test option-leaves-own-sparse-entries-and-empty-array-state
  (multiple-value-bind (state entries)
      (decode-option-test-leaf "3.3a" "status-format" :global-session
                              (format nil "status-format[0] ''~%status-format[7] seven~%status-format[2147483647] last~%"))
    (is (eq state :present))
    (is (typep entries 'simple-vector))
    (is (equalp entries #(("0" . "") ("7" . "seven") ("2147483647" . "last")))))
  (multiple-value-bind (state entries)
      (decode-option-test-leaf "3.3a" "status-format" :global-session (format nil "status-format~%"))
    (is (eq state :present))
    (is (and (typep entries 'simple-vector) (zerop (length entries)))))
  (is (eq :absent (decode-option-test-leaf "3.3a" "status-format" :session "")))
  (multiple-value-bind (state entries)
      (decode-option-test-leaf "3.6" "after-new-window" :global-session
                              (format nil "after-new-window[0] ~%"))
    (is (eq state :present))
    (is (equalp entries #(("0" . ""))))))

(test option-leaves-consume-known-names-and-raw-diagnostics
  (let* ((name (format nil "@line~%%end 7 9 0~%tail"))
         (wire (option-leaf-wire (format nil "~A value~%" name))))
    (multiple-value-bind (state value offset terminal)
        (libtmux.internal::decode-configuration-option-leaf
         wire (libtmux.internal::configuration-catalog "3.3a") name :session 7 9)
      (is (equal (list state value offset terminal) (list :present "value" (length wire) :end)))))
  (let* ((name (format nil "@missing~%%error 7 9 0~%tail"))
         (wire (option-leaf-wire (format nil "invalid option: ~A~%" name) :error)))
    (is (equal (list :missing nil (length wire) :error)
               (multiple-value-list
                (libtmux.internal::decode-configuration-option-leaf
                 wire (libtmux.internal::configuration-catalog "3.8") name :session 7 9)))))
  (signals libtmux:decoding-error (decode-option-test-leaf "3.8" "@missing" :session "")))

(test option-leaves-use-the-exact-printer-profile
  (let ((name (format nil "@a~Cb~Cr$HOME" #\Return #\\)))
    (dolist (version '("3.4" "3.5"))
      (let* ((printed-name (format nil "@a~Crb~Cr~A$HOME" #\\ #\\
                                   (if (string= version "3.4") (string #\\) "")))
             (printed-value (format nil "\"~A$HOME~C~Cn\""
                                    (if (string= version "3.4") (make-string 2 :initial-element #\\)
                                        (string #\\)) #\\ #\\)))
        (is (string= (format nil "$HOME~Cn" #\\)
                     (nth-value 1
                       (decode-option-test-leaf version name :session
                                               (format nil "~A ~A~%" printed-name printed-value)))))))))

(test formatted-option-leaves-validate-types-shapes-and-native-key-order
  (is (null (nth-value 1 (decode-option-test-leaf "3.8" "renumber-windows" :global-session
                         (formatted-option-row "renumber-windows" "''" '(0 1 0 0 0 0 0) "off")))))
  (multiple-value-bind (state entries)
      (decode-option-test-leaf "3.8" "status-format" :global-session
        (concatenate 'string
          (formatted-option-row "status-format" "7" '(1 1 0 1 1 0 0) "seven")
          (formatted-option-row "status-format" "4294967295" '(1 1 0 1 1 0 0) "''")
          (formatted-option-row "status-format" "z" '(1 1 0 1 1 0 0) "last")))
    (is (eq state :present))
    (is (equalp entries #(("7" . "seven") ("4294967295" . "") ("z" . "last")))))
  (is (equalp #() (nth-value 1 (decode-option-test-leaf "3.8" "status-format" :session
                     (formatted-option-row "status-format" "''" '(0 0 0 1 1 0 0) "''")))))
  (is (string= (format nil "bad command~%next")
               (nth-value 1 (decode-option-test-leaf "3.8" "@event" :session
                (formatted-option-row "@event" "''" '(0 1 0 0 1 0 1)
                                      (format nil "\"bad command~Cnnext\"" #\\))
                :hooks-only t)))))

(test option-leaves-refuse-contradictory-records
  (dolist (body (list (format nil "status-format[01] x~%")
                     (format nil "status-format[2147483648] x~%")
                     (format nil "status-format[7] x~%status-format[0] y~%")
                     (format nil "status-format[0] x~%status-format[0] y~%")
                     (format nil "status-format~%status-format[0] x~%")
                     (format nil "status-format[0] x~%status-format~%")
                     (format nil "wrong[0] x~%")
                     (format nil "status-format[0] ~%")))
    (signals libtmux:decoding-error (decode-option-test-leaf "3.3a" "status-format" :session body)))
  (dolist (case '(("status" "false") ("history-limit" "-1")
                  ("history-limit" "+1") ("history-limit" "01")
                  ("mode-keys" "unknown")))
    (signals libtmux:decoding-error
      (decode-option-test-leaf "3.3a" (first case)
                              (if (equal (first case) "mode-keys") :global-window :global-session)
                              (format nil "~A ~A~%" (first case) (second case)))))
  (dolist (flags '((0 1 1 0 0 0 0) (0 1 0 1 0 0 0) (0 1 0 0 1 0 0)
                   (0 1 0 0 0 1 0) (0 1 0 0 0 0 1) (0 2 0 0 0 0 0)))
    (signals libtmux:decoding-error
      (decode-option-test-leaf "3.8" "status" :global-session
                              (formatted-option-row "status" "''" flags "on")))))

(test option-leaves-share-consumption-records-and-native-bounds
  (let* ((body (format nil "status-format[0] ''~%status-format[7] seven~%"))
         (wire (option-leaf-wire body))
         (budget (libtmux.internal::make-configuration-decode-budget
                  :remaining-bytes (length wire) :remaining-frames 0 :remaining-records 2)))
    (is (eq :present (decode-option-test-leaf "3.3a" "status-format" :session body :budget budget)))
    (is (zerop (libtmux.internal::configuration-decode-budget-remaining-bytes budget)))
    (is (zerop (libtmux.internal::configuration-decode-budget-remaining-records budget)))
    (is (zerop (libtmux.internal::configuration-decode-budget-remaining-frames budget)))
    (signals libtmux:output-limit-exceeded
      (decode-option-test-leaf "3.3a" "status-format" :session body
        :budget (libtmux.internal::make-configuration-decode-budget :remaining-records 1)))
    (signals libtmux:output-limit-exceeded
      (decode-option-test-leaf "3.3a" "status-format" :session body
        :budget (libtmux.internal::make-configuration-decode-budget :remaining-bytes (1- (length wire))))))
  (let ((budget (libtmux.internal::make-configuration-decode-budget :remaining-records 2)))
    (is (eq :absent (decode-option-test-leaf "3.3a" "status" :session "" :budget budget)))
    (is (eq :empty (libtmux.internal::decode-configuration-environment-leaf
                   (option-leaf-wire "") (libtmux.internal::encode-utf8 "NAME") 7 9 :budget budget)))
    (is (zerop (libtmux.internal::configuration-decode-budget-remaining-records budget)))
    (signals libtmux:output-limit-exceeded
      (decode-option-test-leaf "3.3a" "status" :session "" :budget budget)))
  (is (string= "" (nth-value 1 (decode-option-test-leaf "3.3a" "@x" :session
                                               (format nil "@x ''~%") :value-limit 0))))
  (signals libtmux:output-limit-exceeded
    (decode-option-test-leaf "3.3a" "@x" :session (format nil "@x 雪~%") :value-limit 2))
  (signals libtmux:output-limit-exceeded
    (decode-option-test-leaf "3.8" "@雪" :session "" :name-limit 3))
  (signals libtmux:output-limit-exceeded
    (decode-option-test-leaf "3.8" "@name" :session "" :name-limit 3))
  (signals libtmux:output-limit-exceeded
    (decode-option-test-leaf "3.8" "status-format" :session
      (formatted-option-row "status-format" "雪" '(1 1 0 1 1 0 0) "value") :key-limit 2)))

(test option-leaves-own-data-and-preserve-absolute-offsets
  (let* ((name (copy-seq "@value"))
         (leaf (option-leaf-wire (format nil "@value retained~%")))
         (wire (concatenate '(vector (unsigned-byte 8)) #(1 2 3) leaf #(255 0 17)))
         (budget (libtmux.internal::make-configuration-decode-budget
                  :check (lambda () (fill name #\x)))))
    (multiple-value-bind (state value offset terminal)
        (libtmux.internal::decode-configuration-option-leaf
         wire (libtmux.internal::configuration-catalog "3.3a") name :session 7 9
         :start 3 :end (+ 3 (length leaf)) :budget budget)
      (fill wire 0)
      (is (equal (list state value offset terminal)
                 (list :present "retained" (+ 3 (length leaf)) :end)))))
  (let* ((name "status-format")
         (body (format nil "status-format[7] owned~%"))
         (first (nth-value 1 (decode-option-test-leaf "3.3a" name :session body)))
         (second (nth-value 1 (decode-option-test-leaf "3.3a" name :session body))))
    (fill (caar (coerce first 'list)) #\x)
    (fill (cdar (coerce first 'list)) #\x)
    (is (equalp second #(("7" . "owned")))))
  (let ((budget (libtmux.internal::make-configuration-decode-budget :remaining-bytes 10000)))
    (setf (libtmux.internal::configuration-decode-budget-check budget)
          (lambda ()
            (when (< (libtmux.internal::configuration-decode-budget-remaining-bytes budget) 9700)
              (error 'libtmux:command-cancelled))))
    (signals libtmux:command-cancelled
      (decode-option-test-leaf "3.3a" "@x" :session
        (format nil "@x ~A~%" (make-string 2048 :initial-element #\a)) :budget budget))))

(test formatted-option-leaves-reject-order-arity-and-wrong-terminal
  (dolist (keys '(("7" "0") ("7" "7") ("a" "7") ("雪" "a")
                  ("01") ("4294967296") ("")))
    (signals libtmux:decoding-error
      (decode-option-test-leaf "3.8" "status-format" :session
        (apply #'concatenate 'string
               (mapcar (lambda (key)
                         (formatted-option-row "status-format" (if (string= key "") "''" key)
                                               '(1 1 0 1 1 0 0) "x")) keys)))))
  (dolist (body (list (format nil "libtmux-option/1~Cstatus~%" #\Tab)
                     (formatted-option-row "status" "''" '(0 1 0 0 0 0 0) (format nil "on~Cextra" #\Tab))
                     (concatenate 'string
                       (formatted-option-row "status" "''" '(0 1 0 0 0 0 0) "on")
                       (formatted-option-row "status" "''" '(0 1 0 0 0 0 0) "off"))))
    (signals libtmux:decoding-error (decode-option-test-leaf "3.8" "status" :session body)))
  (signals libtmux:decoding-error
    (libtmux.internal::decode-configuration-option-leaf
     (option-leaf-wire (format nil "@x value~%") :error)
     (libtmux.internal::configuration-catalog "3.3a") "@x" :session 7 9)))

(test formatted-option-leaves-keep-escaped-keys-and-command-source-inert
  (let* ((key (format nil "\"a~Cntab~Ct雪\"" #\\ #\\))
         (body (formatted-option-row "status-format" key '(1 1 0 1 1 0 0) "''")))
    (is (equalp (vector (cons (format nil "a~%tab~C雪" #\Tab) ""))
                (nth-value 1 (decode-option-test-leaf "3.8" "status-format" :session body)))))
  (let* ((source (format nil "display-message \"a~Cn#{pid}\"" #\\))
         (quoted (format nil "'display-message \"a~C~Cn#{pid}\"'" #\\ #\\)))
    (is (string= source
                 (cdar (coerce (nth-value 1
                         (decode-option-test-leaf "3.8" "after-new-window" :session
                           (formatted-option-row "after-new-window" "0" '(1 1 0 1 0 1 0) quoted)
                           :hooks-only t)) 'list)))))
  (signals libtmux:decoding-error
    (decode-option-test-leaf "3.8" "after-new-window" :session
      (formatted-option-row "after-new-window" "0" '(1 1 0 1 0 1 0)
                            (format nil "'line~Cnbreak'" #\\))))
  (signals libtmux:invalid-argument
    (decode-option-test-leaf "3.8" "status" :session "" :hooks-only t))
  (signals libtmux:invalid-argument
    (decode-option-test-leaf "3.7c" "@event" :session "" :hooks-only t)))

(test option-leaves-refuse-element-syntax-as-a-whole-name
  (let ((name "@missing[broken"))
    (signals libtmux:invalid-argument
      (libtmux.internal::decode-configuration-option-leaf
       (option-leaf-wire (format nil "invalid option: ~A~%" name) :error)
       (libtmux.internal::configuration-catalog "3.8") name :session 7 9)))
  (is (string= "value" (nth-value 1 (decode-option-test-leaf "3.3a" "@name]=value" :session
                                    (format nil "@name]=value value~%"))))))
