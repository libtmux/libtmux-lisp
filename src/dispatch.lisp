(in-package #:libtmux.internal)

(defun format-equal (field value)
  (format nil "#{==:#{~A},~A}" field
          (if (integerp value) (write-to-string value :base 10 :radix nil) value)))

(defun format-conjunction (expressions)
  (reduce (lambda (left right) (format nil "#{&&:~A,~A}" left right))
          expressions :from-end t :initial-value "1"))

(defun target-guard (entity)
  (let ((id (libtmux:id entity)))
    (ecase (libtmux:entity-model entity)
      (:session (values (concatenate 'string id ":") (format-equal "session_id" id)))
      (:window (values id (format-equal "window_id" id)))
      (:pane (values id (format-equal "pane_id" id)))
      (:window-link
       (destructuring-bind (session index window) id
         (values (link-target entity)
                 (format-conjunction (list (format-equal "session_id" session)
                                           (format-equal "window_index" index)
                                           (format-equal "window_id" window))))))
      ;; Floor tmux has no client loop. Preflight checks unique name/fingerprint.
      (:client (values nil nil)))))

(defun receipt-command (receipt)
  (list "list-commands" "-F" receipt "list-sessions"))

(defun server-guard (witness)
  (format-conjunction
   (list (format-equal "pid" (server-witness-pid witness))
         (format-equal "start_time" (server-witness-start witness))
         (format-equal "version" (server-witness-version witness)))))

(defun guarded-command (witness targets arguments nonce)
  (let ((body (tmux-command-list
               (list arguments (receipt-command (concatenate 'string nonce ":complete")))))
        (reject-target (tmux-command-text (receipt-command (concatenate 'string nonce ":target")))))
    (dolist (target (reverse targets))
      (multiple-value-bind (locator guard) (target-guard target)
        (when guard
          (setf body (tmux-command-text (list "if-shell" "-F" "-t" locator guard body reject-target))))))
    (list "-N" "if-shell" "-F" (server-guard witness)
          (concatenate 'string
                       (tmux-command-text (receipt-command (concatenate 'string nonce ":entered")))
                       " ; " body)
          (tmux-command-text (receipt-command (concatenate 'string nonce ":server"))))))

(defun guarded-read-command (witness targets arguments)
  ;; An ordinary tmux client can open raw stdout only once. Refusal commands
  ;; emit stderr; no receipt may consume the byte payload's stdout stream.
  (let ((body (tmux-command-text arguments)))
    (dolist (target (reverse targets))
      (multiple-value-bind (locator guard) (target-guard target)
        (when guard
          (setf body (tmux-command-text
                      (list "if-shell" "-F" "-t" locator guard body
                            "libtmux-internal-read-target-refused"))))))
    (list "-N" "if-shell" "-F" (server-guard witness) body
          "libtmux-internal-read-server-refused")))

(defun interpret-read-outcome (outcome)
  ;; Hooks can reset a command error's exit status, but cannot retract bytes
  ;; already written to the owned stderr pipe. Do not classify their text.
  (when (and (eq (libtmux:outcome-status outcome) :succeeded)
             (plusp (length (slot-value outcome 'libtmux::stderr))))
    (setf (slot-value outcome 'libtmux::status) :failed
          (slot-value outcome 'libtmux::reason) :diagnostic-output))
  (check-outcome outcome))

(defun receipt-bytes (nonce suffix)
  (encode-utf8 (format nil "~A:~A~%" nonce suffix)))

(defun byte-prefix-p (prefix bytes)
  (and (<= (length prefix) (length bytes))
       (not (mismatch prefix bytes :end2 (length prefix)))))

(defun interpret-guarded-outcome (client targets outcome nonce)
  (let* ((bytes (slot-value outcome 'libtmux::stdout))
         (entered (receipt-bytes nonce "entered"))
         (complete (receipt-bytes nonce "complete"))
         (entered-p (byte-prefix-p entered bytes))
         (body (if entered-p (subseq bytes (length entered)) bytes))
         (server-rejected (byte-prefix-p (receipt-bytes nonce "server") body))
         (target-rejected (byte-prefix-p (receipt-bytes nonce "target") body)))
    (when (or server-rejected target-rejected)
      (when server-rejected (invalidate-client-generation client))
      (setf (slot-value outcome 'libtmux::status) :not-dispatched
            (slot-value outcome 'libtmux::phase) :guard-rejected
            (slot-value outcome 'libtmux::reason) (if server-rejected :stale-server :stale-target))
      (error 'libtmux:stale-target :client client :target (first targets) :outcome outcome
             :message "The live dispatch guard rejected the selected server or target"))
    (if entered-p
        (let* ((end (- (length bytes) (length complete)))
               (completed (and (>= end (length entered))
                               (not (mismatch complete bytes :start2 end)))))
          (setf (slot-value outcome 'libtmux::stdout)
                (subseq bytes (length entered) (if completed end (length bytes))))
          (when (and (member (libtmux:outcome-status outcome) '(:succeeded :failed)) (not completed))
            (setf (slot-value outcome 'libtmux::status) :unknown
                  (slot-value outcome 'libtmux::reason) :missing-completion-receipt)))
        (when (member (libtmux:outcome-status outcome) '(:succeeded :failed))
          (setf (slot-value outcome 'libtmux::status) :unknown
                (slot-value outcome 'libtmux::reason) :missing-dispatch-receipt)))
    (when (and (eq (libtmux:outcome-status outcome) :succeeded)
               (plusp (length (slot-value outcome 'libtmux::stderr))))
      (setf (slot-value outcome 'libtmux::status) :unknown
            (slot-value outcome 'libtmux::reason) :diagnostic-output))
    (check-outcome outcome)))

(defun target-context-current-p (client target)
  (let ((snapshot (slot-value target 'libtmux::snapshot)))
    (and (eq (slot-value client 'libtmux::context) (slot-value snapshot 'libtmux::context))
         (= (slot-value client 'libtmux::generation) (slot-value snapshot 'libtmux::generation)))))

(defun preflight-targets (client targets token budget)
  (dolist (target targets)
    (unless (target-context-current-p client target)
      (error 'libtmux:stale-target :target target
             :message "The target belongs to another client or an invalidated generation")))
  (prog1
      (if targets
          (let ((capture (capture-with-retries client token budget 100000)))
            (mapcar (lambda (target) (resolve-observation client target capture)) targets))
          (progn
            (audit-with-budget client token budget)
            (accept-server-witness client (read-server-witness client token budget)) nil))
    (check-capture-budget budget token)
    (unless (plusp (capture-budget-remaining budget))
      (error 'libtmux:output-limit-exceeded :message "Preflight exhausted the operation's byte budget"))))

(defun preflight-failure (client arguments start condition)
  (let* ((original (libtmux:error-outcome condition))
         (outcome (make-outcome (argument-vector (client-argv client arguments))
                                :not-dispatched :preflight start
                                :stdout (and original (libtmux:outcome-stdout original))
                                :stderr (and original (libtmux:outcome-stderr original))
                                :reason :preflight-failed)))
    (error (apply #'make-condition (class-name (class-of condition))
                  :message (libtmux:error-message condition) :cause condition
                  :client client :outcome outcome
                  (typecase condition
                    (libtmux:stale-target (list :target (libtmux:error-target condition)))
                    (libtmux:unsupported-configuration
                     (list :setting (libtmux:error-setting condition)
                           :commands (libtmux:error-commands condition)))
                    (libtmux:unsupported-capability
                     (list :feature (libtmux:error-feature condition)
                           :required-version (libtmux:error-required-version condition)
                           :actual-version (libtmux:error-actual-version condition))))))))

(defun check-command-capability (client feature minimum-version)
  (let ((actual (server-witness-version (slot-value client 'libtmux::witness))))
    (unless (version-at-least-p actual minimum-version)
      (error 'libtmux:unsupported-capability :feature feature
             :required-version minimum-version :actual-version actual
             :message (format nil "~A requires tmux ~A or newer; live daemon is ~A"
                              feature minimum-version actual)))))

(defun command-version-flags (client arguments version-flags)
  (let* ((actual (server-witness-version (slot-value client 'libtmux::witness)))
         (flags (loop for (minimum . flags) in version-flags
                      when (version-at-least-p actual minimum) append flags))
         (boundary (or (position "--" arguments :test #'string=) (length arguments))))
    (append (subseq arguments 0 boundary) flags (nthcdr boundary arguments))))

(defun perform-command (client targets arguments &key input cancel-token timeout output-limit observe
                                                    minimum-version feature version-flags raw-read
                                                    argument-builder)
  (setf timeout (or timeout (slot-value client 'libtmux::timeout))
        output-limit (or output-limit (slot-value client 'libtmux::output-limit))
        arguments (coerce (argument-vector arguments) 'list)
        input (and input (octet-vector input)))
  (check-limits timeout output-limit)
  (check-command-envelope arguments)
  (when (and raw-read (or input observe (not (equal (first arguments) "show-buffer"))))
    (invalid-argument "The payload-only read path is reserved for show-buffer"))
  (handler-bind ((libtmux:libtmux-error
                   (lambda (condition) (setf (slot-value condition 'libtmux::client) client))))
    (call-with-operation
     client cancel-token
     (lambda (token)
       (let* ((start (monotonic-seconds))
              (requested-arguments arguments)
              (budget (make-capture-budget :start start :deadline (+ start timeout)
                                           :remaining output-limit :row-limit 100000 :field-limit 1048576))
              (current (handler-case (prog1 (preflight-targets client targets token budget)
                                      (when minimum-version
                                        (check-command-capability client feature minimum-version)))
                         (libtmux:libtmux-error (condition)
                           (preflight-failure client arguments start condition))))
              (witness (slot-value client 'libtmux::witness))
              (generation (slot-value client 'libtmux::generation))
              (*command-socket-path* (server-witness-endpoint witness))
              (nonce (format nil "libtmux-~32,'0X" (random (ash 1 128) (make-random-state t)))))
         (let* ((prepared
                  (handler-case
                      (let ((value (if argument-builder
                                       (funcall argument-builder witness current)
                                       arguments)))
                        (coerce (argument-vector value) 'list))
                    (libtmux:libtmux-error (condition)
                      (preflight-failure client requested-arguments start condition))))
                (encoded (handler-case
                             (check-command-envelope
                              (let ((effective (command-version-flags client prepared version-flags)))
                                (if raw-read
                                    (guarded-read-command witness current effective)
                                    (guarded-command witness current effective nonce))))
                           (libtmux:libtmux-error (condition)
                             (preflight-failure client requested-arguments start condition))))
                (outcome (execute-tmux client encoded token
                                      (max 0 (- (capture-budget-deadline budget) (monotonic-seconds)))
                                      (capture-budget-remaining budget) input)))
           (decf (capture-budget-remaining budget)
                 (+ (length (slot-value outcome 'libtmux::stdout))
                    (length (slot-value outcome 'libtmux::stderr))))
           (unwind-protect
                (progn
                  (if raw-read
                      (interpret-read-outcome outcome)
                      (interpret-guarded-outcome client targets outcome nonce))
                  (when observe
                    (handler-case
                        (multiple-value-bind (value present-p)
                            (let ((capture (capture-with-retries client token budget 100000)))
                              (unless (= generation (slot-value capture 'libtmux::generation))
                                (error 'libtmux:stale-target
                                       :message "Server changed after the command completed"))
                              (funcall observe outcome capture))
                          (setf (slot-value outcome 'libtmux::value) value
                                (slot-value outcome 'libtmux::present-p) present-p))
                      (error (condition)
                        (setf (slot-value outcome 'libtmux::observation-error) condition))))
                  outcome)
             (setf (slot-value outcome 'libtmux::elapsed) (- (monotonic-seconds) start)))))))))

(defun observe-target (client target)
  (lambda (outcome capture)
    (declare (ignore outcome))
    (values (resolve-observation client target capture) t)))

(defun outcome-text (outcome)
  (handler-bind ((libtmux:decoding-error
                   (lambda (condition) (setf (slot-value condition 'libtmux::outcome) outcome))))
    (strict-text (libtmux:outcome-stdout outcome))))

(defun printed-command (client arguments &rest options)
  (let ((outcome (apply #'perform-command client nil arguments options)))
    (handler-bind ((libtmux:decoding-error
                     (lambda (condition) (setf (slot-value condition 'libtmux::client) client))))
      (values (outcome-text outcome) outcome))))
