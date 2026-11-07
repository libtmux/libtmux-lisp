(in-package #:libtmux.tests)

(in-suite integration)

(defun captured-by-id (values id)
  (or (find id values :key #'libtmux:id :test #'equal)
      (error "Missing captured fixture entity ~S" id)))

(test explicit-entity-termination-preserves-unselected-entities
  "Removing one captured target must not broaden to its siblings."
  (with-tmux-fixture (fixture)
    (fixture-ok fixture "split-window" "-d" "-t" "fixture:0" "/bin/cat")
    (fixture-ok fixture "new-window" "-d" "-t" "fixture" "-n" "disposable" "/bin/cat")
    (fixture-ok fixture "new-session" "-d" "-s" "disposable-session" "/bin/cat")
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (pane-id (string-trim '(#\Newline #\Return)
                                   (fixture-ok fixture "display-message" "-p" "-t"
                                               "fixture:0.1" "#{pane_id}")))
             (window-id (string-trim '(#\Newline #\Return)
                                     (fixture-ok fixture "display-message" "-p" "-t"
                                                 "fixture:disposable" "#{window_id}")))
             (session-id (string-trim '(#\Newline #\Return)
                                      (fixture-ok fixture "display-message" "-p" "-t"
                                                  "disposable-session" "#{session_id}")))
             (pane (captured-by-id (libtmux:panes snapshot) pane-id))
             (window (captured-by-id (libtmux:windows snapshot) window-id))
             (session (captured-by-id (libtmux:sessions snapshot) session-id)))
        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:kill-pane client pane))))
        (is (not (search pane-id (fixture-ok fixture "list-panes" "-a" "-F"
                                             "#{pane_id}"))))
        (is (zerop (nth-value 2 (fixture-command fixture "has-session" "-t" "fixture"))))
        (handler-case
            (progn (libtmux:kill-pane client pane)
                   (fail "A removed pane was dispatched again"))
          (libtmux:stale-target (condition)
            (is (eq :not-dispatched
                    (libtmux:outcome-status (libtmux:error-outcome condition))))))

        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:kill-window client window))))
        (is (not (search window-id (fixture-ok fixture "list-windows" "-a" "-F"
                                               "#{window_id}"))))
        (is (zerop (nth-value 2 (fixture-command fixture "has-session" "-t" "fixture"))))

        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:kill-session client session))))
        (is (= 1 (nth-value 2 (fixture-command fixture "has-session" "-t"
                                               "disposable-session"))))
        (is (zerop (nth-value 2 (fixture-command fixture "has-session" "-t" "fixture"))))))))

(test explicit-server-termination-proves-daemon-exit
  "Server termination must prove the retained daemon exited and keep captures local."
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (session (aref (libtmux:sessions snapshot) 0))
             (outcome (libtmux:kill-server client)))
        (is (eq :succeeded (libtmux:outcome-status outcome)))
        (is (eq :server-terminated (libtmux:outcome-phase outcome)))
        (is (sb-sys:wait-until-fd-usable (fixture-pidfd fixture) :input 0))
        (is (libtmux:client-open-p client))
        (is (equal "fixture" (libtmux:name session)))
        (signals libtmux:libtmux-error (libtmux:fetch-snapshot client))))))

(defclass termination-receipt-loss-transport (libtmux.internal::subprocess-transport) ())

(defclass termination-pre-dispatch-cancel-transport
    (libtmux.internal::subprocess-transport) ())

(defclass termination-late-cancel-transport
    (libtmux.internal::subprocess-transport)
  ((server-pidfd :initarg :server-pidfd)))

(defun server-termination-command-p (argv)
  (some (lambda (argument) (search "kill-server" argument)) argv))

(defmethod libtmux.internal::execute-command :around
    ((transport termination-pre-dispatch-cancel-transport) argv
     &key input timeout output-limit cancel-token keep-input-open)
  (declare (ignore input timeout output-limit keep-input-open))
  (when (server-termination-command-p argv)
    (libtmux:cancel cancel-token))
  (call-next-method))

(defmethod libtmux.internal::execute-command :around
    ((transport termination-late-cancel-transport) argv
     &key input timeout output-limit cancel-token keep-input-open)
  (declare (ignore input timeout output-limit keep-input-open))
  (let ((outcome (call-next-method)))
    (when (server-termination-command-p argv)
      (unless (sb-sys:wait-until-fd-usable
               (slot-value transport 'server-pidfd) :input 0.25)
        (error "The terminated fixture daemon did not become pidfd-readable"))
      (libtmux:cancel cancel-token))
    outcome))

(defmethod libtmux.internal::execute-command :around
    ((transport termination-receipt-loss-transport) argv
     &key input timeout output-limit cancel-token keep-input-open)
  (declare (ignore input timeout output-limit cancel-token keep-input-open))
  (let ((outcome (call-next-method)))
    (when (server-termination-command-p argv)
      (setf (slot-value outcome 'libtmux::stdout)
            (make-array 0 :element-type '(unsigned-byte 8))))
    outcome))

(test server-termination-preserves-not-dispatched-outcome
  "Cancellation before executable release must remain certainly not dispatched."
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (libtmux:fetch-snapshot client)
      (setf (slot-value client 'libtmux::transport)
            (make-instance 'termination-pre-dispatch-cancel-transport))
      (let ((token (libtmux:make-cancellation-token)))
        (handler-case
            (progn (libtmux:kill-server client :cancel-token token)
                   (fail "A cancelled pre-dispatch server command succeeded"))
          (libtmux:command-cancelled (condition)
            (let ((outcome (libtmux:error-outcome condition)))
              (is (eq :not-dispatched (libtmux:outcome-status outcome)))
              (is (eq :cancelled (libtmux:outcome-reason outcome)))))))
      (is (zerop (nth-value 2 (fixture-command fixture "has-session" "-t" "fixture")))))))

(test proven-server-exit-precedes-late-cancellation
  "A readable retained pidfd must win over cancellation requested after exit."
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (libtmux:fetch-snapshot client)
      (setf (slot-value client 'libtmux::transport)
            (make-instance 'termination-late-cancel-transport
                           :server-pidfd (fixture-pidfd fixture)))
      (let* ((token (libtmux:make-cancellation-token))
             (outcome (libtmux:kill-server client :cancel-token token)))
        (is (libtmux:cancelled-p token))
        (is (eq :succeeded (libtmux:outcome-status outcome)))
        (is (eq :server-terminated (libtmux:outcome-phase outcome)))))))

(test server-exit-observation-failure-retains-outcome
  "A post-dispatch wait failure must retain uncertainty and its original cause."
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (libtmux:fetch-snapshot client)
      (let ((libtmux.internal::*server-death-waiter*
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error 'libtmux:command-failed :message "Injected server wait failure"))))
        (handler-case
            (progn (libtmux:kill-server client)
                   (fail "A failed server-exit observation lost its uncertainty"))
          (libtmux:outcome-unknown (condition)
            (is (typep (libtmux:error-cause condition) 'libtmux:command-failed))
            (is (eq :unknown
                    (libtmux:outcome-status (libtmux:error-outcome condition))))
            (is (eq :server-exit-unobserved
                    (libtmux:outcome-reason (libtmux:error-outcome condition))))))))))

(test server-death-without-dispatch-receipt-remains-unknown
  "Concurrent death cannot substitute for evidence that this call dispatched."
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (libtmux:fetch-snapshot client)
      (setf (slot-value client 'libtmux::transport)
            (make-instance 'termination-receipt-loss-transport))
      (handler-case
          (progn (libtmux:kill-server client)
                 (fail "Server death without a dispatch receipt became certain"))
        (libtmux:outcome-unknown (condition)
          (is (eq :unknown
                  (libtmux:outcome-status (libtmux:error-outcome condition))))
          (is (eq :missing-dispatch-receipt
                  (libtmux:outcome-reason (libtmux:error-outcome condition))))))
      (is (sb-sys:wait-until-fd-usable (fixture-pidfd fixture) :input 0)))))
