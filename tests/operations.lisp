(in-package #:libtmux.tests)

(in-suite integration)

(test original-consumer-context-is-checked-after-targetless-preflight
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((generation (slot-value client 'libtmux::generation))
             (replaced nil) (checked 0)
             (libtmux.internal::*dispatch-context-check*
               (lambda (actual witness current)
                 (declare (ignore witness current))
                 (assert (eq actual client))
                 (incf checked)
                 (unless (= generation (slot-value client 'libtmux::generation))
                   (error 'libtmux:stale-target :message "Original consumer generation changed"))))
             (libtmux.internal::*process-launched-hook*
               (lambda (job)
                 (declare (ignore job))
                 (unless replaced
                   (setf replaced t)
                   (fixture-ok fixture "kill-server")
                   (fixture-ok fixture "new-session" "-d" "-s" "replacement" "/bin/cat")))))
        (declare (special libtmux.internal::*dispatch-context-check*))
        (signals libtmux:stale-target
          (libtmux:new-session client :name "must-not-create" :command #("/bin/cat")))
        (is-true replaced)
        (is (= 1 checked))
        (is (not (search "must-not-create" (fixture-ok fixture "list-sessions" "-F" "#{session_name}"))))))))

(test consumer-context-check-precedes-the-existing-argument-builder
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((events nil)
             (libtmux.internal::*dispatch-context-check*
               (lambda (actual witness current) (declare (ignore actual witness current)) (push :context events)))
             (outcome
               (locally (declare (special libtmux.internal::*dispatch-context-check*))
                 (libtmux.internal::perform-command
                  client nil '("display-message" "-p" "prepared")
                  :argument-builder (lambda (witness current)
                                      (declare (ignore witness current))
                                      (push :builder events) '("display-message" "-p" "prepared"))))))
        (declare (special libtmux.internal::*dispatch-context-check*))
        (is (eq :succeeded (libtmux:outcome-status outcome)))
        (is (equal '(:context :builder) (nreverse events)))))))

(test guarded-literals-and-replacement-observations
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (window (aref (libtmux:windows snapshot) 0))
             (pane (aref (libtmux:panes snapshot) 0))
             (old-name (libtmux:name window))
             (name "literal-#{pid};'λ;#[one]##[two]###[three]####[four]#[#{pid}];tail#")
             (outcome (libtmux:rename-window client window name)))
        (is (eq :succeeded (libtmux:outcome-status outcome)))
        (multiple-value-bind (replacement present-p) (libtmux:outcome-value outcome)
          (is (eq t present-p))
          (is (libtmux:same-entity-p window replacement))
          (is (equal name (libtmux:name replacement))))
        (is (equal old-name (libtmux:name window)))
        (let* ((outcome (libtmux:rename-window client window "pid-#{pid}" :format-p t))
               (replacement (libtmux:outcome-value outcome)))
          (is (equal (format nil "pid-~D" (fixture-pid fixture)) (libtmux:name replacement))))
        (is (equalp (libtmux.internal::encode-utf8 (libtmux:capture-pane client pane))
                    (libtmux:capture-pane-bytes client pane)))
        (let* ((text (format nil "λ'\";~C  #comment~C~C$HOME`x`\\~A;" #\Newline #\Tab #\Return "~"))
               (outcome (libtmux.internal::perform-command
                         client nil (list "set-environment" "-g" "LIBTMUX_ENCODING_TEST" text))))
          (is (eq :succeeded (libtmux:outcome-status outcome)))
          ;; show-environment's display escaping differs between releases.
          ;; Read the bytes inherited by a pane, outside that printer.
          (let ((path (merge-pathnames "environment.bin" (fixture-directory fixture)))
                (program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux"))
                (channel "environment-written"))
            (fixture-ok fixture "set-environment" "-u" "-t" "fixture" "LIBTMUX_ENCODING_TEST")
            (fixture-ok fixture "new-window" "-d" "-t" "fixture" "/bin/sh" "-c"
                        "printf '%s' \"$LIBTMUX_ENCODING_TEST\" > \"$1\" && exec \"$2\" -N -S \"$3\" wait-for -S \"$4\""
                        "environment-probe" (namestring path) program (fixture-socket fixture) channel)
            (is (eq :succeeded
                    (libtmux:outcome-status
                     (libtmux.internal::run-process
                      (list program "-N" "-S" (fixture-socket fixture) "wait-for" channel)
                      :timeout 0.5))))
            (is (equalp (libtmux.internal::encode-utf8 text) (read-file-octets path)))))))))

(test successful-mutation-retains-failed-observation
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((window (aref (libtmux:fetch-windows client) 0)) (dispatched nil))
        (let* ((libtmux.internal::*before-dispatch-hook*
                 (lambda (job)
                   (cond ((find "if-shell" (libtmux.internal::process-job-argv job) :test #'equal)
                          (setf dispatched t))
                         (dispatched
                          (error 'libtmux:command-failed :message "Injected follow-up observation failure")))))
               (outcome (libtmux:rename-window client window "mutation-succeeded")))
          (is (eq :succeeded (libtmux:outcome-status outcome)))
          (is (not (nth-value 1 (libtmux:outcome-value outcome))))
          (is (typep (libtmux:outcome-observation-error outcome) 'libtmux:libtmux-error))
          (is (equal (format nil "mutation-succeeded~%")
                     (fixture-ok fixture "display-message" "-p" "-t" "@0" "#{window_name}"))))))))

(test live-link-guard-rejects-renumbering-after-preflight
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((link (aref (libtmux:window-links (libtmux:fetch-snapshot client)) 0))
             (changed nil)
             (libtmux.internal::*before-dispatch-hook*
               (lambda (job)
                 (when (and (not changed)
                            (find "if-shell" (libtmux.internal::process-job-argv job) :test #'equal))
                   (setf changed t)
                   (fixture-ok fixture "move-window" "-s" "fixture:0" "-t" "fixture:4")
                   (fixture-ok fixture "new-window" "-d" "-t" "fixture:0" "/bin/cat")))))
        (handler-case
            (progn (libtmux:select-window client link) (fail "Stale link was dispatched"))
          (libtmux:stale-target (condition)
            (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))
            (is (eq :guard-rejected (libtmux:outcome-phase (libtmux:error-outcome condition))))))
        (is (eq t changed))
        (is (equal (format nil "4~%")
                   (fixture-ok fixture "display-message" "-p" "-t" "fixture" "#{window_index}")))))))

(test mutation-guard-rejects-foreign-daemon
  (with-tmux-fixture (first)
    (with-tmux-fixture (second)
      (with-fixture-client (client first)
        (let* ((window (aref (libtmux:fetch-windows client) 0))
               (old (libtmux:name window))
               (foreign (fixture-ok second "display-message" "-p" "#{window_name}"))
               (selected (fixture-socket first))
               (backup (concatenate 'string selected "-saved"))
               (changed nil))
          (unwind-protect
               (let ((libtmux.internal::*before-dispatch-hook*
                       (lambda (job)
                         (when (and (not changed)
                                    (find "if-shell" (libtmux.internal::process-job-argv job) :test #'equal))
                           (sb-posix:rename selected backup)
                           (sb-posix:symlink (fixture-socket second) selected)
                           (setf changed t)))))
                 (handler-case
                     (progn (libtmux:rename-window client window "must-not-run")
                            (fail "Foreign daemon received a mutation"))
                   (libtmux:stale-target (condition)
                     (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))
                     (is (eq :stale-server (libtmux:outcome-reason (libtmux:error-outcome condition)))))))
            (when changed
              (sb-posix:unlink selected)
              (sb-posix:rename backup selected)))
          (is (equal (format nil "~A~%" old) (fixture-ok first "display-message" "-p" "#{window_name}")))
          (is (equal foreign (fixture-ok second "display-message" "-p" "#{window_name}"))))))))

(test operational-failure-attribution
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((window (aref (libtmux:fetch-windows client) 0))
            (token (libtmux:make-cancellation-token)))
        (libtmux:cancel token)
        (handler-case
            (progn (libtmux:rename-window client window "never" :cancel-token token)
                   (fail "Pre-cancelled rename ran"))
          (libtmux:command-cancelled (condition)
            (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))
            (is (eq :preflight (libtmux:outcome-phase (libtmux:error-outcome condition))))))
        (with-fixture-client (other fixture)
          (let ((calls 0))
            (let ((libtmux.internal::*process-started-hook*
                    (lambda (process) (declare (ignore process)) (incf calls))))
              (signals libtmux:stale-target (libtmux:rename-window other window "never")))
            (is (zerop calls)))))
      (handler-case
          (progn
            (libtmux.internal::perform-command
             client nil (list "load-buffer" "-b" "missing" (concatenate 'string (fixture-socket fixture) "-missing")))
            (fail "Asynchronous load failure became success"))
        (libtmux:command-failed (condition)
          (is (eq :failed (libtmux:outcome-status (libtmux:error-outcome condition))))
          (is (= 1 (libtmux:outcome-exit-code (libtmux:error-outcome condition)))))))))

(defclass receipt-loss-transport (libtmux.internal::subprocess-transport)
  ((keep-entry :initarg :keep-entry)))

(defmethod libtmux.internal::execute-command :around
    ((transport receipt-loss-transport) argv &key input timeout output-limit cancel-token keep-input-open)
  (declare (ignore input timeout output-limit cancel-token keep-input-open))
  (let ((outcome (call-next-method)))
    (when (find "if-shell" argv :test #'equal)
      (let* ((bytes (libtmux:outcome-stdout outcome))
             (end (if (slot-value transport 'keep-entry) (1+ (position 10 bytes)) 0)))
        (setf (slot-value outcome 'libtmux::stdout) (subseq bytes 0 end)
              (slot-value outcome 'libtmux::status) :failed
              (slot-value outcome 'libtmux::exit-code) 1
              (slot-value outcome 'libtmux::reason) :exit)))
    outcome))

(test completed-mutation-with-lost-receipts-remains-unknown
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((window (aref (libtmux:fetch-windows client) 0)))
        (dolist (keep-entry '(nil t))
          (setf (slot-value client 'libtmux::transport)
                (make-instance 'receipt-loss-transport :keep-entry keep-entry))
          (handler-case
              (progn (libtmux:rename-window client window "performed" :observe nil)
                     (fail "Receipt loss became a certain outcome"))
            (libtmux:outcome-unknown (condition)
              (is (eq :unknown (libtmux:outcome-status (libtmux:error-outcome condition))))
              (is (= 1 (libtmux:outcome-exit-code (libtmux:error-outcome condition))))))
          (is (equal (format nil "performed~%")
                     (fixture-ok fixture "display-message" "-p" "#{window_name}"))))
        (setf (slot-value client 'libtmux::transport) (make-instance 'libtmux.internal::subprocess-transport))
        (let ((*print-base* 16) (*print-radix* t))
          (is (eq :succeeded (libtmux:outcome-status
                             (libtmux:rename-window client window "decimal-guard" :observe nil)))))))))

(test successful-hook-does-not-hide-buffer-transfer-failure
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (libtmux:set-buffer client "payload" :name "data")
      (fixture-ok fixture "set-hook" "-g" "after-save-buffer" "run-shell 'printf recovered'")
      ;; The receipt already opened stdout; this second raw stream fails.
      ;; A successful hook still resets the process exit to zero.
      (handler-case
          (progn
            (libtmux.internal::perform-command client nil '("save-buffer" "-b" "data" "-"))
            (fail "A successful hook hid a failed byte transfer"))
        (libtmux:outcome-unknown (condition)
          (let ((outcome (libtmux:error-outcome condition)))
            (is (eq :diagnostic-output (libtmux:outcome-reason outcome)))
            (is (= 0 (libtmux:outcome-exit-code outcome)))
            (is (plusp (length (libtmux:outcome-stderr outcome))))))))))

(test conflicting-command-aliases-fail-before-payload
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (window (aref (libtmux:windows snapshot) 0)))
        (fixture-ok fixture "set-option" "-s" "command-alias[100]"
                    "rename-window=set-option -g @unexpected yes ; rename-window")
        (handler-case
            (progn (libtmux:rename-window client window "never")
                   (fail "Overridden built-in was invoked"))
          (libtmux:unsupported-configuration (condition)
            (is (eq :command-alias (libtmux:error-setting condition)))
            (is (equalp #("rename-window") (libtmux:error-commands condition)))
            (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))))
        (is (= 1 (nth-value 2 (fixture-command fixture "show-options" "-g" "@unexpected"))))
        (fixture-ok fixture "set-option" "-su" "command-alias[100]")
        (fixture-ok fixture "set-option" "-s" "command-alias[101]"
                    "list-panes=set-option -g @unexpected yes ; list-panes")
        (signals libtmux:unsupported-configuration (libtmux:fetch-snapshot client))
        (is (= 1 (nth-value 2 (fixture-command fixture "show-options" "-g" "@unexpected"))))
        (fixture-ok fixture "set-option" "-su" "command-alias[101]")
        (fixture-ok fixture "set-option" "-s" "command-alias[101]"
                    "lock-session=set-option -g @unexpected yes")
        (signals libtmux:unsupported-configuration
          (libtmux:lock-session client (aref (libtmux:sessions snapshot) 0)))
        (is (= 1 (nth-value 2 (fixture-command fixture "show-options" "-g" "@unexpected"))))
        (fixture-ok fixture "set-option" "-su" "command-alias[101]")
        (fixture-ok fixture "set-option" "-s" "command-alias[102]" "project-rename=rename-window")
        (is (eq :succeeded (libtmux:outcome-status (libtmux:rename-window client window "allowed" :observe nil))))))))

(test typed-configuration-mutations-preserve-native-state
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (session (aref (libtmux:sessions snapshot) 0))
             (window (aref (libtmux:windows snapshot) 0))
             (pane (aref (libtmux:panes snapshot) 0)))
        (is (eq :succeeded
                (libtmux:outcome-status
                 (libtmux:set-option client "mouse" t
                                      :scope :session :target session))))
        (is (equal (format nil "on~%")
                   (fixture-ok fixture "show-options" "-v" "-t" "fixture" "mouse")))
        (libtmux:set-option client "mouse" nil :scope :session :target session)
        (is (equal (format nil "off~%")
                   (fixture-ok fixture "show-options" "-v" "-t" "fixture" "mouse")))
        (libtmux:set-option client "status-format" "literal #{pid}"
                             :scope :session :target session :key 7)
        (is (equal (format nil "literal #{pid}~%")
                   (fixture-ok fixture "show-options" "-v" "-t" "fixture"
                               "status-format[7]")))
        (libtmux:unset-option client "status-format"
                               :scope :session :target session :key 7)
        (is (not (search "status-format[7]"
                         (fixture-ok fixture "show-options" "-t" "fixture"
                                     "status-format"))))

        (libtmux:set-option client "@literal" "#{pid}" :scope :server)
        (is (equal (format nil "#{pid}~%")
                   (fixture-ok fixture "show-options" "-sv" "@literal")))
        (libtmux:set-option client "@literal" "#{pid}"
                             :scope :server :format-p t)
        (is (equal (format nil "~D~%" (fixture-pid fixture))
                   (fixture-ok fixture "show-options" "-sv" "@literal")))
        (libtmux:unset-option client "@literal" :scope :server)

        (libtmux:set-hook client "after-new-window" "set-option -g @hook-ran yes"
                           :scope :session :target session)
        (is (= 1 (nth-value 2
                            (fixture-command fixture "show-options" "-gv" "@hook-ran"))))
        (is (search "set-option -g @hook-ran yes"
                    (fixture-ok fixture "show-hooks" "-t" "fixture" "after-new-window")))
        (libtmux:unset-hook client "after-new-window"
                             :scope :session :target session)

        (let ((text (format nil "empty and λ~Cnext" #\Newline)))
          (libtmux:set-environment client "LIBTMUX_MUTATION_TEST" text
                                    :scope :global :hidden t)
          (is (equal (format nil "LIBTMUX_MUTATION_TEST=~A~%" text)
                     (fixture-ok fixture "show-environment" "-gh"
                                 "LIBTMUX_MUTATION_TEST")))
          (libtmux:remove-environment client "LIBTMUX_MUTATION_TEST"
                                       :scope :global)
          (is (equal (format nil "-LIBTMUX_MUTATION_TEST~%")
                     (fixture-ok fixture "show-environment" "-gh"
                                 "LIBTMUX_MUTATION_TEST")))
          (libtmux:unset-environment client "LIBTMUX_MUTATION_TEST"
                                      :scope :global)
          (is (= 1 (nth-value 2
                              (fixture-command fixture "show-environment" "-g"
                                               "LIBTMUX_MUTATION_TEST")))))
        (libtmux:set-environment client "LIBTMUX_SESSION_TEST" "#{pid}"
                                  :scope :session :target session :format-p t)
        (is (equal (format nil "LIBTMUX_SESSION_TEST=~D~%" (fixture-pid fixture))
                   (fixture-ok fixture "show-environment" "-t" "fixture"
                               "LIBTMUX_SESSION_TEST")))
        (libtmux:unset-environment client "LIBTMUX_SESSION_TEST"
                                    :scope :session :target session)

        (let* ((payload-dispatched nil)
               (libtmux.internal::*before-dispatch-hook*
                (lambda (job)
                  (when (some (lambda (argument) (search "set-option" argument))
                              (libtmux.internal::process-job-argv job))
                    (setf payload-dispatched t)))))
          (signals libtmux:invalid-argument
            (libtmux:set-option client "mouse" "on"
                                 :scope :session :target session))
          (is (null payload-dispatched)))
        (signals libtmux:invalid-argument
          (libtmux:set-option client "@bad/name" "x" :scope :server))
        (signals libtmux:invalid-argument
          (libtmux:set-option client "remain-on-exit" "on"
                               :scope :pane :target window))
        (signals libtmux:invalid-argument
          (libtmux:set-environment client "BAD-NAME" "x" :scope :global))
        (signals libtmux:invalid-argument
          (libtmux:set-environment client "X" "x"
                                    :scope :session :target pane))))))

(test conditional-option-writes-preserve-local-state
  "Outer: absent-only writes require an owned tmux option table."
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((session (aref (libtmux:sessions (libtmux:fetch-snapshot client)) 0))
             (setter (symbol-function 'libtmux:set-option)))
        (flet ((value (name)
                 (fixture-ok fixture "show-options" "-v" "-t" "fixture" name))
               (refused (name replacement &rest options)
                 (let ((condition (handler-case
                                      (apply setter client name replacement
                                             :scope :session :target session
                                             :only-if-unset t options)
                                    (libtmux:libtmux-error (caught) caught))))
                   (is (typep condition 'libtmux:libtmux-error))
                   (when (typep condition 'libtmux:libtmux-error)
                     (is (typep (libtmux:error-outcome condition) 'libtmux:command-outcome))))))
          (fixture-ok fixture "set-option" "-g" "@local_claim" "inherited")
          (is (eq :succeeded
                  (libtmux:outcome-status
                   (funcall setter client "@local_claim" "first"
                            :scope :session :target session :only-if-unset t))))
          (is (string= (format nil "first~%") (value "@local_claim")))
          (refused "@local_claim" "replacement")
          (is (string= (format nil "first~%") (value "@local_claim")))
          (fixture-ok fixture "set-option" "-t" "fixture" "@empty_claim" "")
          (refused "@empty_claim" "replacement")
          (is (string= (format nil "~%") (value "@empty_claim")))
          (fixture-ok fixture "set-option" "-t" "fixture" "status-format[8]" "other")
          (funcall setter client "status-format" "first"
                   :scope :session :target session :key 9 :only-if-unset t)
          (refused "status-format" "replacement" :key 9)
          (is (string= (format nil "first~%") (value "status-format[9]")))
          (is (string= (format nil "other~%") (value "status-format[8]")))
          (libtmux:set-option client "@local_claim" "replacement"
                               :scope :session :target session)
          (is (string= (format nil "replacement~%") (value "@local_claim"))))))))

(test configuration-printers-preserve-native-text-and-outcomes
  "Live printer output is inspection data; endpoint execution belongs in the outer loop."
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (session (aref (libtmux:sessions snapshot) 0))
             (name "@literal#{pid}")
             (environment-name "two words #{pid}")
             (value (format nil "λ #{literal}~%  next")))
        (fixture-ok fixture "set-option" "-s" "@literal##{pid}" value)
        (multiple-value-bind (text outcome)
            (libtmux:show-options-text client :scope :server :name name)
          (is (string= (fixture-ok fixture "show-options" "-s" "@literal##{pid}") text))
          (is (eq :succeeded (libtmux:outcome-status outcome)))
          (setf (char text 0) #\X)
          (is (not (char= #\X (char (libtmux.internal::strict-text
                                     (libtmux:outcome-stdout outcome)) 0)))))
        (multiple-value-bind (text outcome)
            (libtmux:show-options-text client :scope :session :target session
                                       :name "status" :include-inherited t :value-only t)
          (is (string= (fixture-ok fixture "show-options" "-A" "-v" "-t" "fixture" "status") text))
          (is (eq :succeeded (libtmux:outcome-status outcome))))
        (fixture-ok fixture "set-hook" "-g" "after-new-window" "display-message -p hook-source")
        (multiple-value-bind (text outcome)
            (libtmux:show-hooks-text client :scope :global-session :name "after-new-window")
          (is (string= (fixture-ok fixture "show-hooks" "-g" "after-new-window") text))
          (is (search "display-message" text))
          (is (eq :succeeded (libtmux:outcome-status outcome))))
        (fixture-ok fixture "set-environment" "-gh" environment-name value)
        (multiple-value-bind (text outcome)
            (libtmux:show-environment-text client :scope :global :name environment-name :hidden t)
          (is (string= (fixture-ok fixture "show-environment" "-gh" environment-name) text))
          (is (eq :succeeded (libtmux:outcome-status outcome))))
        (multiple-value-bind (text outcome)
            (libtmux:show-environment-text client :scope :global :name environment-name
                                           :hidden t :shell-format t)
          (is (string= (fixture-ok fixture "show-environment" "-ghs" environment-name) text))
          (is (eq :succeeded (libtmux:outcome-status outcome))))
        (is (string= "" (libtmux:show-environment-text
                         client :scope :global :name environment-name)))
        (fixture-ok fixture "set-environment" "-g" "--" "-h" "literal-name")
        (is (string= (format nil "-h=literal-name~%")
                     (libtmux:show-environment-text client :scope :global :name "-h")))
        (fixture-ok fixture "set-environment" "-t" "fixture" "LIBTMUX_PRINT_TEST" "")
        (is (string= (format nil "LIBTMUX_PRINT_TEST=~%")
                     (libtmux:show-environment-text client :scope :session :target session
                                                    :name "LIBTMUX_PRINT_TEST")))
        (fixture-ok fixture "set-environment" "-r" "-t" "fixture" "LIBTMUX_PRINT_TEST")
        (is (string= (format nil "-LIBTMUX_PRINT_TEST~%")
                     (libtmux:show-environment-text client :scope :session :target session
                                                    :name "LIBTMUX_PRINT_TEST")))
        (let ((installed nil))
          (unwind-protect
               (let ((libtmux.internal::*before-dispatch-hook*
                       (lambda (job)
                         (when (and (not installed)
                                    (some (lambda (argument)
                                            (and (search "show-options" argument)
                                                 (search "status" argument)
                                                 (search "libtmux-" argument)))
                                          (libtmux.internal::process-job-argv job)))
                           (fixture-ok fixture "set-hook" "-t" "fixture" "after-show-options"
                                       "display-message -p printer-hook")
                           (setf installed t)))))
                 (is (search "printer-hook"
                             (libtmux:show-options-text client :scope :session :target session
                                                       :name "status" :include-inherited t))))
            (when installed (fixture-ok fixture "set-hook" "-u" "-t" "fixture" "after-show-options"))))))))

(test configuration-printer-validation-and-versioned-output
  "Input validation and live feature gates must precede the selected printer."
  (let ((client (make-instance 'libtmux:client)) (started 0))
    (let ((libtmux.internal::*process-started-hook* (lambda (process)
                                                   (declare (ignore process)) (incf started))))
      (signals libtmux:invalid-argument (libtmux:show-hooks-text client :scope :server))
      (signals libtmux:invalid-argument (libtmux:show-options-text client :scope :session))
      (signals libtmux:invalid-argument
        (libtmux:show-options-text client :scope :server :format 42))
      (signals libtmux:invalid-argument
        (libtmux:show-environment-text client :scope :global :name "bad=name"))
      (signals libtmux:invalid-argument (libtmux:show-environment-text client :scope :session))
      (is (zerop started))))
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (session (aref (libtmux:sessions snapshot) 0))
             (modern (libtmux.internal::version-at-least-p
                      (libtmux.internal::server-witness-version
                       (slot-value client 'libtmux::witness)) "3.8"))
             (format "#{option_name}=#{option_value}"))
        ;; Deliberately disagree with the cached executable release: use the live witness.
        (setf (slot-value client 'libtmux::version) (if modern "3.3a" "3.8"))
        (fixture-ok fixture "set-hook" "-g" "after-new-window" "display-message -p source")
        (if modern
            (progn
              (is (string= (fixture-ok fixture "show-options" "-g" "-F" format "status")
                           (libtmux:show-options-text client :scope :global-session
                                                      :name "status" :format format)))
              (is (string= (fixture-ok fixture "show-hooks" "-g" "-F" format "after-new-window")
                           (libtmux:show-hooks-text client :scope :global-session
                                                    :name "after-new-window" :format format)))
              (is (string= (fixture-ok fixture "show-hooks" "-gB")
                           (libtmux:show-hooks-text client :scope :global-session :monitors t))))
            (dolist (operation (list (lambda () (libtmux:show-options-text
                                                client :scope :global-session :format format))
                                    (lambda () (libtmux:show-hooks-text
                                                client :scope :global-session :format format))
                                    (lambda () (libtmux:show-hooks-text
                                                client :scope :global-session :monitors t))))
              (let ((condition (handler-case (funcall operation)
                                 (libtmux:unsupported-capability (caught) caught))))
                (is (typep condition 'libtmux:unsupported-capability))
                (is (string= "3.8" (libtmux:error-required-version condition)))
                (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition)))))))
        (let ((condition (handler-case
                             (libtmux:show-environment-text client :scope :global
                                                           :name "LIBTMUX_PRINT_MISSING")
                           (libtmux:command-failed (caught) caught))))
          (is (typep condition 'libtmux:command-failed))
          (is (eq client (libtmux:error-client condition)))
          (is (search "LIBTMUX_PRINT_MISSING"
                      (libtmux.internal::strict-text
                       (libtmux:outcome-stderr (libtmux:error-outcome condition))))))
        (libtmux:with-client (other :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                    :socket-path (fixture-socket fixture))
          (signals libtmux:stale-target
            (libtmux:show-options-text other :scope :session :target session)))
        (uiop:run-program
         (list "/usr/bin/python3" "-c"
               "import os,sys; os.execvp(os.fsencode(sys.argv[1]), [os.fsencode(x) for x in sys.argv[1:]] + [bytes([255])])"
               (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux") "-S" (fixture-socket fixture)
               "-N" "set-option" "-s" "@invalid-utf8")
         :force-shell nil :input nil :output :string :error-output :string)
        (if (eq :direct
                (libtmux.internal::configuration-option-profile
                 (libtmux.internal::configuration-catalog
                  (libtmux.internal::server-witness-version
                   (slot-value client 'libtmux::witness)))))
            (let ((condition (handler-case
                                 (libtmux:show-options-text client :scope :server
                                                           :name "@invalid-utf8" :value-only t)
                               (libtmux:decoding-error (caught) caught))))
              (is (typep condition 'libtmux:decoding-error))
              (is (eq client (libtmux:error-client condition)))
              (is (equalp #(255 10) (libtmux:outcome-stdout (libtmux:error-outcome condition)))))
            (multiple-value-bind (text outcome)
                (libtmux:show-options-text client :scope :server :name "@invalid-utf8" :value-only t)
              (is (string= (fixture-ok fixture "show-options" "-sv" "@invalid-utf8") text))
              (is (eq :succeeded (libtmux:outcome-status outcome)))))))))

(test live-operation-preconditions-refuse-changed-state
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((window (aref (libtmux:fetch-windows client) 0))
             (name (libtmux:name window))
             (control "@libtmux-operation-state")
             (expression (format nil "#{==:#{~A},EXPECTED}" control))
             (generation (slot-value client 'libtmux::generation))
             (caught nil) (changed nil) (after-guard 0))
        (fixture-ok fixture "set-option" "-s" control "EXPECTED")
        (let ((libtmux.internal::*dispatch-preconditions* (list (list nil expression)))
              (libtmux.internal::*before-dispatch-hook*
                (lambda (job)
                  (when changed (incf after-guard))
                  (when (and (not changed)
                             (find "if-shell" (libtmux.internal::process-job-argv job)
                                   :test #'equal))
                    (setf changed t)
                    (fixture-ok fixture "set-option" "-s" control "OTHER")))))
          (declare (special libtmux.internal::*dispatch-preconditions*))
          (handler-case (libtmux:rename-window client window "must-not-run")
            (libtmux:libtmux-error (condition) (setf caught condition))))
        (is (not (null changed)))
        (is (not (null caught)))
        (when caught
          (is (typep caught 'libtmux.internal::dispatch-precondition-failed))
          (is (eq window (libtmux:error-target caught)))
          (let ((outcome (libtmux:error-outcome caught)))
            (is (eq :not-dispatched (libtmux:outcome-status outcome)))
            (is (eq :guard-rejected (libtmux:outcome-phase outcome)))
            (is (eq :operation-precondition (libtmux:outcome-reason outcome)))))
        (is (zerop after-guard))
        (is (= generation (slot-value client 'libtmux::generation)))
        (is (string= (format nil "~A~%" name)
                     (fixture-ok fixture "display-message" "-p" "-t"
                                 (libtmux:id window) "#{window_name}")))
        (fixture-ok fixture "set-option" "-s" control "EXPECTED")
        (let ((libtmux.internal::*dispatch-preconditions* (list (list nil expression)))
              (libtmux.internal::*before-dispatch-hook*
                (lambda (job)
                  (declare (ignore job))
                  (setf (char expression 0) #\0))))
          (declare (special libtmux.internal::*dispatch-preconditions*))
          (is (eq :succeeded (libtmux:outcome-status
                              (libtmux:rename-window client window "guard-owned" :observe nil)))))
        (let* ((snapshot (libtmux:fetch-snapshot client))
               (fresh (find (libtmux:id window) (libtmux:windows snapshot)
                            :key #'libtmux:id :test #'string=))
               (pane-sequence (format nil "~{~A.~}"
                                      (map 'list #'libtmux:id (libtmux:panes fresh))))
               (libtmux.internal::*dispatch-preconditions*
                 (list (list (libtmux:id fresh)
                             (format nil "#{==:#{P:#{pane_id}.},~A}" pane-sequence))))
               (added nil)
               (libtmux.internal::*before-dispatch-hook*
                 (lambda (job)
                   (when (and (not added)
                              (find "if-shell" (libtmux.internal::process-job-argv job)
                                    :test #'equal))
                     (setf added t)
                     (fixture-ok fixture "split-window" "-d" "-t"
                                 (libtmux:id fresh) "/bin/cat")))))
          (declare (special libtmux.internal::*dispatch-preconditions*))
          (signals libtmux:libtmux-error
            (libtmux:select-layout client fresh :tiled :observe nil))
          (is (not (null added))))
        (let ((libtmux.internal::*dispatch-preconditions*
                (list (list nil (make-string 20000 :initial-element #\1)))))
          (declare (special libtmux.internal::*dispatch-preconditions*))
          (signals libtmux:invalid-argument
            (libtmux:rename-window client window "oversized-guard" :observe nil)))
        (let ((libtmux.internal::*dispatch-preconditions* '((nil "1"))))
          (declare (special libtmux.internal::*dispatch-preconditions*))
          (signals libtmux:invalid-argument
            (libtmux.internal::perform-command client nil '("show-buffer") :raw-read t)))))))
