(in-package #:libtmux.internal)

(defun terminate-entity (client target model command options)
  (apply #'perform-command client (list target)
         (list command "-t" (physical-target target model))
         options))

(defun server-termination-command (witness nonce)
  (let ((entered (receipt-command (concatenate 'string nonce ":entered")))
        (rejected (receipt-command (concatenate 'string nonce ":server"))))
    (list "-N" "if-shell" "-F" (server-guard witness)
          (tmux-command-list (list entered '("kill-server")))
          (tmux-command-text rejected))))

(defun wait-for-server-death (witness token deadline)
  (let ((wake (cancellation-event-open))
        (registered nil))
    (when (minusp wake)
      (error 'libtmux:command-failed
             :message "Cannot allocate the server-termination cancellation descriptor"))
    (unwind-protect
         (progn
           (when (member :server
                         (poll-owned (list (list :server (server-witness-fd witness) :input)) 0))
             (return-from wait-for-server-death :terminated))
           (unless (setf registered (register-token token wake))
             (return-from wait-for-server-death :cancelled))
           (loop
             (let ((remaining (- deadline (monotonic-seconds))))
               (let ((ready (poll-owned
                             (list (list :server (server-witness-fd witness) :input)
                                   (list :cancel wake :input))
                             (max 0 remaining))))
                 (when (member :server ready)
                   (return :terminated))
                 (when (or (member :cancel ready) (libtmux:cancelled-p token))
                   (return :cancelled))
                 (unless (plusp remaining)
                   (return :deadline))))))
      (if registered
          (retire-token token wake)
          (close-descriptor wake)))))

(defvar *server-death-waiter* #'wait-for-server-death)

(defun interpret-server-termination (client witness token deadline outcome nonce)
  (let* ((bytes (slot-value outcome 'libtmux::stdout))
         (entered (receipt-bytes nonce "entered"))
         (rejected (receipt-bytes nonce "server"))
         (entered-p (byte-prefix-p entered bytes))
         (rejected-p (byte-prefix-p rejected bytes)))
    (when (eq :not-dispatched (libtmux:outcome-status outcome))
      (check-outcome outcome))
    (when rejected-p
      (invalidate-client-generation client)
      (setf (slot-value outcome 'libtmux::status) :not-dispatched
            (slot-value outcome 'libtmux::phase) :guard-rejected
            (slot-value outcome 'libtmux::reason) :stale-server)
      (error 'libtmux:stale-target :client client :outcome outcome
             :message "The live dispatch guard rejected the selected server"))
    (when entered-p
      (setf (slot-value outcome 'libtmux::stdout) (subseq bytes (length entered))))
    (ecase (handler-case (funcall *server-death-waiter* witness token deadline)
             (error (condition)
               (setf (slot-value outcome 'libtmux::status) :unknown
                     (slot-value outcome 'libtmux::reason) :server-exit-unobserved)
               (error 'libtmux:outcome-unknown :cause condition :outcome outcome
                      :message "Cannot prove whether the selected tmux server exited")))
      (:terminated
       (invalidate-client-generation client)
       (setf (slot-value outcome 'libtmux::phase) :server-terminated
             (slot-value outcome 'libtmux::status) (if entered-p :succeeded :unknown)
             (slot-value outcome 'libtmux::reason) (unless entered-p :missing-dispatch-receipt)))
      (:cancelled
       (setf (slot-value outcome 'libtmux::status) :unknown
             (slot-value outcome 'libtmux::reason) :cancelled))
      (:deadline
       (setf (slot-value outcome 'libtmux::status) :unknown
             (slot-value outcome 'libtmux::reason) :deadline)))
    (check-outcome outcome)))

(defun perform-server-termination (client &key cancel-token timeout output-limit)
  (setf timeout (or timeout (slot-value client 'libtmux::timeout))
        output-limit (or output-limit (slot-value client 'libtmux::output-limit)))
  (check-limits timeout output-limit)
  (handler-bind ((libtmux:libtmux-error
                   (lambda (condition) (setf (slot-value condition 'libtmux::client) client))))
    (call-with-operation
     client cancel-token
     (lambda (token)
       (let* ((start (monotonic-seconds))
              (deadline (+ start timeout))
              (budget (make-capture-budget :start start :deadline deadline
                                           :remaining output-limit :row-limit 100000
                                           :field-limit 1048576))
              (current (handler-case (preflight-targets client nil token budget)
                         (libtmux:libtmux-error (condition)
                           (preflight-failure client '("kill-server") start condition))))
              (witness (slot-value client 'libtmux::witness))
              (*command-socket-path* (server-witness-endpoint witness))
              (nonce (format nil "libtmux-~32,'0X"
                             (random (ash 1 128) (make-random-state t))))
              (encoded (handler-case
                           (check-command-envelope
                            (server-termination-command witness nonce))
                         (libtmux:libtmux-error (condition)
                           (preflight-failure client '("kill-server") start condition))))
              (outcome (execute-tmux client encoded token
                                     (max 0 (- deadline (monotonic-seconds)))
                                     (capture-budget-remaining budget) nil)))
         (declare (ignore current))
         (unwind-protect
              (interpret-server-termination client witness token deadline outcome nonce)
           (setf (slot-value outcome 'libtmux::elapsed)
                 (- (monotonic-seconds) start))))))))

(in-package #:libtmux)

(defun kill-pane (client pane &key cancel-token timeout output-limit)
  "Delete exactly the captured physical PANE and return a COMMAND-OUTCOME.
The live pane identity is checked before dispatch. Other panes are preserved.
Signals STALE-TARGET when PANE disappeared or belongs to another generation.
Never retries the mutation.

See also: KILL-WINDOW, KILL-SESSION, KILL-SERVER"
  (libtmux.internal::terminate-entity
   client pane :pane "kill-pane"
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun kill-window (client window &key cancel-token timeout output-limit)
  "Delete exactly the captured physical WINDOW and return a COMMAND-OUTCOME.
Every link to that physical window is removed by tmux. Other windows remain.
The live identity is checked before dispatch; the mutation is never retried.

See also: KILL-PANE, KILL-SESSION, KILL-SERVER"
  (libtmux.internal::terminate-entity
   client window :window "kill-window"
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun kill-session (client session &key cancel-token timeout output-limit)
  "Delete exactly the captured SESSION and return a COMMAND-OUTCOME.
Tmux removes that session's links and panes no longer referenced elsewhere.
The live identity is checked before dispatch; the mutation is never retried.

See also: KILL-PANE, KILL-WINDOW, KILL-SERVER"
  (libtmux.internal::terminate-entity
   client session :session "kill-session"
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun kill-server (client &key cancel-token timeout output-limit)
  "Terminate CLIENT's preflight-accepted daemon and return a COMMAND-OUTCOME.
Success requires both a pre-dispatch receipt and observed exit of the server
process accepted during this call. Missing evidence signals OUTCOME-UNKNOWN;
cancellation or a deadline never causes an automatic retry. The connection
CLIENT stays open but its generation is invalidated after observed server death.
A failed exit wait retains :SERVER-EXIT-UNOBSERVED and the underlying
ERROR-CAUSE. CLOSE-CLIENT never calls this function.

See also: CLOSE-CLIENT, KILL-SESSION, OUTCOME-STATUS, OUTCOME-PHASE"
  (libtmux.internal::perform-server-termination
   client :cancel-token cancel-token :timeout timeout :output-limit output-limit))
