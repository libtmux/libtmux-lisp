(in-package #:libtmux.internal)

(defun outcome-text (outcome)
  (handler-bind ((libtmux:decoding-error
                   (lambda (condition) (setf (slot-value condition 'libtmux::outcome) outcome))))
    (strict-text (libtmux:outcome-stdout outcome))))

(defun rename-entity (client target model text format-p observe options)
  (apply #'perform-command client (list target)
         (list (ecase model (:session "rename-session") (:window "rename-window"))
               "-t" (physical-target target model) "--"
               (if format-p (text-argument text "Name format") (literal-format text)))
         :observe (when observe (observe-target client target)) options))

(in-package #:libtmux)

(defun rename-window (client window text &key format-p (observe t) cancel-token timeout output-limit)
  "Rename the selected physical WINDOW and return a COMMAND-OUTCOME.
TEXT is literal by default; FORMAT-P explicitly enables tmux format expansion.
Tmux may normalize or reject names. OBSERVE acquires a replacement in
OUTCOME-VALUE; a failed follow-up stays in OUTCOME-OBSERVATION-ERROR without
erasing successful mutation. Earlier observations are unchanged. Signals
STALE-TARGET or an operational condition. Never retries the mutation."
  (libtmux.internal::rename-entity client window :window text format-p observe
                                  (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun rename-session (client session text &key format-p (observe t) cancel-token timeout output-limit)
  "Rename SESSION with literal TEXT, or an explicit FORMAT-P expression.
Return a COMMAND-OUTCOME. OBSERVE defaults true and supplies a replacement
through OUTCOME-VALUE; observation failure is retained separately. Tmux enforces
session-name restrictions and uniqueness. Signals STALE-TARGET or an operational
condition. Timeout and byte limits cover preflight, mutation and observation."
  (libtmux.internal::rename-entity client session :session text format-p observe
                                  (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun select-window (client link &key (observe t) cancel-token timeout output-limit)
  "Select a captured window LINK within its session; return a COMMAND-OUTCOME.
The expected session/index/window mapping is checked before dispatch. OBSERVE
supplies a replacement link through OUTCOME-VALUE. A moved or replaced mapping
signals STALE-TARGET; external failures retain their command outcome."
  (libtmux.internal::perform-command
   client (list link) (list "select-window" "-t" (libtmux.internal::link-target link))
   :observe (when observe (libtmux.internal::observe-target client link))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun select-pane (client pane &key (observe t) cancel-token timeout output-limit)
  "Select PANE within its physical window; return a COMMAND-OUTCOME.
OBSERVE supplies a replacement pane through OUTCOME-VALUE. Captured getters
stay local and unchanged. Signals STALE-TARGET or an operational condition."
  (libtmux.internal::perform-command
   client (list pane) (list "select-pane" "-t" (libtmux.internal::physical-target pane :pane))
   :observe (when observe (libtmux.internal::observe-target client pane))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun capture-pane-bytes (client pane &key start end join-lines escape-sequences
                                          escape-controls alternate pending-output
                                          cancel-token timeout output-limit)
  "Read PANE now; return owned output octets and the diagnostic command outcome.
START/END accept signed line numbers or :ALL for the corresponding history edge.
JOIN-LINES joins wrapped rows; ESCAPE-SEQUENCES retains terminal styles;
ESCAPE-CONTROLS asks tmux to render controls as octal; ALTERNATE selects its
alternate screen; PENDING-OUTPUT requests tmux's pending input bytes. Tmux owns
these capture modes and may reject unavailable combinations. Does not decode or
trim bytes. Signals STALE-TARGET or an operational condition with its outcome."
  (let ((arguments (list "capture-pane" "-p" "-t" (libtmux.internal::physical-target pane :pane))))
    (loop for value in (list join-lines escape-sequences escape-controls alternate pending-output)
          for flag in '("-J" "-e" "-C" "-a" "-P")
          when value do (setf arguments (append arguments (list flag))))
    (loop for value in (list start end) for flag in '("-S" "-E")
          when value do (setf arguments
                              (append arguments (list flag (if (eq value :all) "-"
                                                               (libtmux.internal::integer-argument
                                                                value (- 2147483647) 2147483647 "Line"))))))
    (let ((outcome (libtmux.internal::perform-command
                    client (list pane) arguments :cancel-token cancel-token
                    :timeout timeout :output-limit output-limit)))
      (values (outcome-stdout outcome) outcome))))

(defun capture-pane (client pane &rest options)
  "Read PANE now; return strict UTF-8 text and the diagnostic command outcome.
Preserve whitespace and trailing lines.
OPTIONS are the CAPTURE-PANE-BYTES options. Invalid UTF-8 signals DECODING-ERROR;
call CAPTURE-PANE-BYTES when byte preservation is required."
  (multiple-value-bind (bytes outcome) (apply #'capture-pane-bytes client pane options)
    (handler-bind ((decoding-error (lambda (condition)
                                    (setf (slot-value condition 'outcome) outcome
                                          (slot-value condition 'client) client))))
      (values (libtmux.internal::strict-text bytes) outcome))))
