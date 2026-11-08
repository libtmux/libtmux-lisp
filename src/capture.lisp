(in-package #:libtmux.internal)

(defstruct capture-budget start deadline remaining row-limit field-limit)

(defun check-capture-budget (budget token)
  (when (libtmux:cancelled-p token)
    (error 'libtmux:command-cancelled :message "Operation was cancelled"))
  (unless (< (monotonic-seconds) (capture-budget-deadline budget))
    (error 'libtmux:deadline-exceeded :message "Operation exceeded its total deadline")))

(defun verify-listing-witness (client rows witness)
  (unless (and (= (length rows) 1)
               (= (row-value (aref rows 0) :server/pid) (server-witness-pid witness))
               (= (row-value (aref rows 0) :server/start-time) (server-witness-start witness))
               (equal (row-value (aref rows 0) :server/socket-path) (server-witness-socket witness))
               (equal (row-value (aref rows 0) :server/version) (server-witness-version witness))
               (server-witness-fd witness)
               (null (poll-owned (list (list :server (server-witness-fd witness) :input)) 0)))
    (invalidate-client-generation client)
    (inconsistent-capture "A listing connected to a different tmux server")))

(defun execute-capture-command (client arguments token budget)
  (check-capture-budget budget token)
  (let ((remaining-time (- (capture-budget-deadline budget) (monotonic-seconds))))
    (unless (plusp remaining-time)
      (error 'libtmux:deadline-exceeded :message "Snapshot acquisition exceeded its total deadline"))
    (unless (plusp (capture-budget-remaining budget))
      (error 'libtmux:output-limit-exceeded :message "Snapshot acquisition exceeded its total byte limit"))
    (let ((outcome (check-outcome
                    (execute-tmux client arguments token remaining-time
                                  (capture-budget-remaining budget) nil))))
      (decf (capture-budget-remaining budget)
            (+ (length (slot-value outcome 'libtmux::stdout))
               (length (slot-value outcome 'libtmux::stderr))))
      outcome)))

(defun capture-command (client name token budget &optional witness)
  (let ((outcome (execute-capture-command
                  client (if witness
                             (append (row-command :witness) '(";") (rest (row-command name)))
                             (row-command name)) token budget)))
    (handler-bind ((libtmux:libtmux-error
                     (lambda (condition)
                       (setf (slot-value condition 'libtmux::outcome) outcome))))
      (let* ((bytes (slot-value outcome 'libtmux::stdout))
             (start (if witness
                        (1+ (or (position 10 bytes)
                                (inconsistent-capture "Missing listing connection witness")))
                        0)))
        (when witness
          (verify-listing-witness
           client (decode-rows :witness (subseq bytes 0 start) :row-limit 1
                                       :field-limit (capture-budget-field-limit budget)) witness))
        (decode-rows name (make-array (- (length bytes) start) :element-type '(unsigned-byte 8)
                                     :displaced-to bytes :displaced-index-offset start)
                     :row-limit (capture-budget-row-limit budget)
                     :field-limit (capture-budget-field-limit budget)
                     :check-budget (lambda () (check-capture-budget budget token)))))))

(defun capture-listing-batch (client token budget witness)
  (let ((outcome (execute-capture-command client (listing-batch-command) token budget)))
    (handler-bind ((libtmux:libtmux-error
                     (lambda (condition)
                       (setf (slot-value condition 'libtmux::outcome) outcome))))
      (decode-listing-batch
       (slot-value outcome 'libtmux::stdout)
       (lambda (rows) (verify-listing-witness client rows witness))
       :row-limit (capture-budget-row-limit budget)
       :field-limit (capture-budget-field-limit budget)
       :check-budget (lambda () (check-capture-budget budget token))))))

(defun read-server-witness (client token budget)
  (handler-case
      (let ((rows (capture-command client :witness token budget)))
        (unless (= 1 (length rows))
          (inconsistent-capture "Expected exactly one live tmux server witness"))
        (witness-from-row client (aref rows 0)))
    (error (condition)
      (invalidate-client-generation client)
      (error condition))))

(defun audit-with-budget (client token budget)
  (check-capture-budget budget token)
  (unless (plusp (capture-budget-remaining budget))
    (error 'libtmux:output-limit-exceeded :message "Operation exhausted its byte budget before configuration audit"))
  (let ((outcome (audit-command-aliases
                  client token (max 0 (- (capture-budget-deadline budget) (monotonic-seconds)))
                  (capture-budget-remaining budget))))
    (decf (capture-budget-remaining budget)
          (+ (length (slot-value outcome 'libtmux::stdout))
             (length (slot-value outcome 'libtmux::stderr))))))

(defun acquire-snapshot (client token budget entity-limit)
  (audit-with-budget client token budget)
  (let* ((start (monotonic-seconds)) (wall-start (get-universal-time))
         (before (accept-server-witness client (read-server-witness client token budget))))
    (let* ((*command-socket-path* (server-witness-endpoint before))
           (session-rows (capture-command client :session token budget before))
           (link-rows #()) (pane-rows #()) (client-rows #()) (after nil))
      (when (plusp (length session-rows))
        (multiple-value-setq (link-rows pane-rows client-rows)
          (capture-listing-batch client token budget before)))
      (unwind-protect
           (progn
             (setf after (read-server-witness client token budget))
             (unless (same-witness-p before after)
               (accept-server-witness client after)
               (setf after nil)
               (inconsistent-capture "Tmux server changed during snapshot acquisition"))
             (check-capture-budget budget token)
             (build-snapshot
              (slot-value client 'libtmux::context) (slot-value client 'libtmux::generation)
              (append (witness-provenance before)
                      (list :executable-version (libtmux:tmux-version client)
                            :acquired-monotonic-start start :acquired-monotonic-end (monotonic-seconds)
                            :acquired-universal-start wall-start :acquired-universal-end (get-universal-time)))
              session-rows link-rows pane-rows client-rows :entity-limit entity-limit
              :check-budget (lambda () (check-capture-budget budget token))))
        (close-witness after)))))

(defun capture-with-retries (client token budget entity-limit)
  (loop for attempt below 3
        do (handler-case
               (return (acquire-snapshot client token budget entity-limit))
             (libtmux:incomplete-snapshot (condition)
               (when (= attempt 2) (error condition))))))

(defun resolve-observation (client observation new)
  (let ((old (etypecase observation
               (libtmux:snapshot observation)
               (libtmux:entity (slot-value observation 'libtmux::snapshot)))))
    (unless (and (eq (slot-value old 'libtmux::context) (slot-value new 'libtmux::context))
                 (= (slot-value old 'libtmux::generation) (slot-value new 'libtmux::generation)))
      (error 'libtmux:stale-target :client client :target observation
             :message "The capture belongs to an older server context"))
    (when (typep observation 'libtmux:snapshot) (return-from resolve-observation new))
    (let* ((values (captured-collection new (libtmux:entity-model observation)))
           (matches
             (if (typep observation 'libtmux:attached-client)
                 (remove-if (complement (lambda (value) (string= (libtmux:name value) (libtmux:name observation)))) values)
                 (remove-if (complement (lambda (value) (libtmux:same-entity-p value observation))) values))))
      (unless (= (length matches) 1)
        (error 'libtmux:stale-target :client client :target observation
               :message "Captured target is missing or ambiguous"))
      (let ((result (aref matches 0)))
        (when (typep observation 'libtmux:attached-client)
          (unless (and (nth-value 1 (libtmux:field-value observation :client/created))
                       (every (lambda (field)
                                (equal (multiple-value-list (libtmux:field-value observation field))
                                       (multiple-value-list (libtmux:field-value result field))))
                              '(:client/pid :client/created :client/tty)))
            (error 'libtmux:stale-target :client client :target observation
                   :message "Attached-client target was replaced or cannot be verified")))
        result))))

(in-package #:libtmux)

(defun fetch-snapshot (client &key cancel-token (timeout (slot-value client 'timeout))
                                  (output-limit (slot-value client 'output-limit))
                                  (row-limit 100000) (entity-limit 100000) (field-limit 1048576))
  "Acquire an eager native graph; all later accessors on it are local.
TIMEOUT controls one acquisition deadline and OUTPUT-LIMIT caps combined output,
including at most two retries after contradictory observations. Synchronous
setup and additional cleanup can extend caller wall time. ROW-LIMIT bounds each listing;
ENTITY-LIMIT bounds the complete graph; FIELD-LIMIT bounds encoded field bytes.
No daemon is started. A live daemon with zero sessions yields empty vectors;
connection/listing failures remain errors. Closing CLIENT leaves this snapshot
usable. This is an interval observation, not a transactional snapshot.
See also: FETCH-PANES, PROVENANCE, REFRESH, ERROR-OUTCOME."
  (libtmux.internal::check-limits timeout output-limit)
  (dolist (limit (list row-limit entity-limit field-limit))
    (unless (typep limit '(integer 1))
      (libtmux.internal::invalid-argument "Capture count/field limits must be positive integers")))
  (handler-bind ((libtmux-error
                   (lambda (condition) (setf (slot-value condition 'client) client))))
    (libtmux.internal::call-with-operation
     client cancel-token
     (lambda (token)
       (let* ((start (libtmux.internal::monotonic-seconds))
              (budget (libtmux.internal::make-capture-budget
                       :start start :deadline (+ start timeout) :remaining output-limit
                       :row-limit row-limit :field-limit field-limit)))
         (libtmux.internal::capture-with-retries client token budget entity-limit))))))

(defun fetch-sessions (client &rest options)
  "Acquire a complete snapshot and return its fresh session vector. OPTIONS go to FETCH-SNAPSHOT."
  (sessions (apply #'fetch-snapshot client options)))
(defun fetch-windows (client &rest options)
  "Acquire a complete snapshot and return physical windows once each. OPTIONS go to FETCH-SNAPSHOT."
  (windows (apply #'fetch-snapshot client options)))
(defun fetch-panes (client &rest options)
  "Acquire a complete snapshot and return physical panes once each. OPTIONS go to FETCH-SNAPSHOT."
  (panes (apply #'fetch-snapshot client options)))
(defun fetch-clients (client &rest options)
  "Acquire a complete snapshot and return every attached-client row. OPTIONS go to FETCH-SNAPSHOT."
  (clients (apply #'fetch-snapshot client options)))

(defun refresh (client observation &rest options)
  "Acquire a replacement observation, leaving the earlier capture unchanged.
CLIENT must own the original context/generation. Missing or replaced targets
signal STALE-TARGET. Attached-client refresh requires one unique live target
name with the same PID/creation/tty fingerprint; its observation identity changes."
  (let* ((old (etypecase observation (snapshot observation) (entity (slot-value observation 'snapshot))))
         (new (progn
                (unless (eq (slot-value old 'context) (slot-value client 'context))
                  (error 'stale-target :client client :target observation
                         :message "The capture belongs to another client context"))
                (apply #'fetch-snapshot client options))))
    (libtmux.internal::resolve-observation client observation new)))
