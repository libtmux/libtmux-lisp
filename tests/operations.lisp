(in-package #:libtmux.tests)

(in-suite integration)

(test guarded-literals-and-replacement-observations
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (window (aref (libtmux:windows snapshot) 0))
             (pane (aref (libtmux:panes snapshot) 0))
             (old-name (libtmux:name window))
             (name "literal-#{pid};'λ;")
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
          (is (equal (format nil "LIBTMUX_ENCODING_TEST=~A~%" text)
                     (fixture-ok fixture "show-environment" "-g" "LIBTMUX_ENCODING_TEST"))))))))

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
      (let ((window (aref (libtmux:fetch-windows client) 0)))
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
        (fixture-ok fixture "set-option" "-s" "command-alias[102]" "project-rename=rename-window")
        (is (eq :succeeded (libtmux:outcome-status (libtmux:rename-window client window "allowed" :observe nil))))))))
