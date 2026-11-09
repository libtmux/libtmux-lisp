(in-package #:libtmux.tests)

(in-suite control-integration)

(test control-native-notifications-stay-separate-from-command-replies
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Native notification separation requires tmux 3.8")
          (let* ((capture (libtmux:fetch-snapshot client))
                 (session (aref (libtmux:sessions capture) 0))
                 (window (aref (libtmux:windows capture) 0))
                 (pane (aref (libtmux:panes capture) 0))
                 (session-name (libtmux:name session)) (window-name (libtmux:name window)))
            (libtmux.control:with-connection (connection client session :timeout 1)
              (let* ((launched 0)
                     (libtmux.internal::*process-launched-hook* (lambda (job) (declare (ignore job)) (incf launched))))
                (labels ((command (arguments)
                           (multiple-value-bind (result delivery)
                               (libtmux.control:await-request
                                (libtmux.control:submit-command connection arguments :effect :mutation :timeout 1)
                                :timeout 1)
                             (is (eq :ready delivery))
                             (is (eq :completed (getf result :status)))
                             (getf result :output))))
                  (let ((text "%window-renamed @3 this is command output"))
                    (is (equalp (libtmux.internal::encode-utf8 (format nil "~A~%" text))
                                (command (list "display-message" "-p" "-l" text)))))
                  (command (list "rename-window" "-t" (libtmux:id window) "event-window"))
                  (command (list "rename-session" "-t" (libtmux:id session) "event-session"))
                  (command '("set-buffer" "-b" "control-events" "value"))
                  (command '("delete-buffer" "-b" "control-events"))
                  (let ((new-pane (string-right-trim
                                   '(#\Newline)
                                   (libtmux.internal::decode-utf8
                                    (command (list "split-window" "-d" "-P" "-F" "#{pane_id}"
                                                   "-t" (libtmux:id pane) "/bin/cat"))))))
                    (command (list "select-layout" "-t" (libtmux:id window) "even-horizontal"))
                    (command (list "select-pane" "-t" new-pane))
                    (is (zerop (length (command (list "refresh-client" "-A" (format nil "~A:pause" (libtmux:id pane)))))))
                    (is (zerop (length (command (list "refresh-client" "-A" (format nil "~A:continue" (libtmux:id pane)))))))
                    (let* ((missing (mapcar #'libtmux.internal::encode-utf8
                                     (list (format nil "%window-renamed ~A event-window" (libtmux:id window))
                                           (format nil "%session-renamed ~A event-session" (libtmux:id session))
                                           "%paste-buffer-changed control-events" "%paste-buffer-deleted control-events"
                                           (format nil "%layout-change ~A " (libtmux:id window))
                                           (format nil "%window-pane-changed ~A ~A" (libtmux:id window) new-pane)
                                           (format nil "%pause ~A" (libtmux:id pane))
                                           (format nil "%continue ~A" (libtmux:id pane)))))
                           (deadline (+ (libtmux.internal::monotonic-seconds) 1)))
                      (loop while missing
                            for remaining = (max 0 (- deadline (libtmux.internal::monotonic-seconds)))
                            do (multiple-value-bind (event delivery) (libtmux.control:next-event connection :timeout remaining)
                                 (unless (eq :ready delivery) (return))
                                 (is (not (member (getf event :kind) '(:gap :end))))
                                 (when (eq :notification (getf event :kind))
                                   (setf missing (remove-if
                                                  (lambda (prefix) (libtmux.internal::byte-prefix-p prefix (getf event :data)))
                                                  missing)))))
                      (is (null missing)))))
                (is (zerop launched))
                (is (string= session-name (libtmux:name session)))
                (is (string= window-name (libtmux:name window))))))))))

(test control-ready-refuses-a-mismatched-daemon-witness
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Persistent control readiness requires tmux 3.8 or newer")
          (let* ((session (aref (libtmux:fetch-sessions client) 0))
                 (actual (slot-value client 'libtmux::witness))
                 (expected (libtmux.internal::copy-server-witness actual))
                 (candidate nil) (failure nil))
            (incf (libtmux.internal::server-witness-pid expected))
            (unwind-protect
                 (progn
                   (libtmux.internal::call-with-operation
                    client nil
                    (lambda (token)
                      (let* ((start (libtmux.internal::monotonic-seconds))
                             (budget (libtmux.internal::make-capture-budget
                                      :start start :deadline (+ start 1) :remaining 1048576
                                      :row-limit 100000 :field-limit 1048576)))
                        (handler-case
                            (setf candidate (libtmux.internal::attach-control-peer client session token budget expected
                                              :request-limit 16 :event-limit 256 :event-byte-limit 4194304
                                              :reply-byte-limit 1048576))
                          (libtmux.internal::control-start-failed (condition)
                            (setf failure condition candidate (libtmux.internal::failed-control-peer condition)))))))
                   (is (typep failure 'libtmux.internal::control-start-failed))
                   (when failure
                     (is (not (typep (libtmux:error-cause failure) 'libtmux:deadline-exceeded))))
                   (is (libtmux:client-open-p client))
                   (is (eq actual (slot-value client 'libtmux::witness))))
              (when candidate (libtmux.internal::close-control-peer candidate))))))))

(test control-attachment-preserves-the-session-environment
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Persistent control attachment requires tmux 3.8 or newer")
          (let* ((session (aref (libtmux:fetch-sessions client) 0))
                 (name "LIBTMUX_CONTROL_ENVIRONMENT_FIXTURE")
                 (value (concatenate 'string "session:" (or (uiop:getenv name) "absent")))
                 (old nil))
            (libtmux:set-option client "update-environment" name :scope :session :target session)
            (libtmux:set-environment client name value :scope :session :target session)
            (libtmux.control:with-connection (connection client session :timeout 1)
              (setf old connection)
              (is (eq :ready (libtmux.control:connection-state connection)))
              (libtmux.control:submit-command connection '("detach-client") :effect :mutation)
              (let ((peer (libtmux.control::%peer connection)))
                (is (eq :ready (nth-value 1 (libtmux.internal::wait-control-value
                                            peer (lambda () (libtmux.internal::control-peer-finished peer)) 0.8))))))
            (libtmux.control:with-reconnection (connection capture old :timeout 1)
              (is (eq :ready (libtmux.control:connection-state connection)))
              (let ((current (find (libtmux:id session) (libtmux:sessions capture) :key #'libtmux:id :test #'string=)))
                (is (equal value
                           (getf (aref (libtmux:show-environment client :scope :session :target current
                                                                      :names (vector name)) 0) :value))))))))))

(test control-soft-timer-wakes-the-supervisor-without-aborting-the-process
  (let* ((start (libtmux.internal::monotonic-seconds))
         (job (libtmux.internal::make-process-job
               :argv (libtmux.internal::argument-vector
                      '("/usr/bin/python3" "-u" "-c" "print('ready', flush=True); input(); print('done', flush=True)"))
               :input (libtmux.internal::octet-vector #()) :keep-input-open t
               :environment (libtmux.internal::process-environment)
               :token (libtmux:make-cancellation-token) :cap 1024
               :start start :deadline (+ start 0.8)))
         (armed nil) (sent nil))
    (unwind-protect
         (progn
           (is (libtmux.internal::acquire-job job))
           (libtmux.internal::supervise-job
            job :before-step
            (lambda (owned)
              (cond
                ((and (not armed) (libtmux.internal::process-job-released owned)
                      (null (libtmux.internal::process-job-status owned))
                      (search #(114 101 97 100 121 10) (aref (libtmux.internal::process-job-buffers owned) 0)))
                 (setf armed t
                       (libtmux.internal::process-job-poll-deadline owned)
                       (- (libtmux.internal::monotonic-seconds) 1)))
                ((and armed (not sent))
                 (setf sent t
                       (libtmux.internal::process-job-poll-deadline owned) nil
                       (libtmux.internal::process-job-input owned) (libtmux.internal::octet-vector #(120 10))
                       (libtmux.internal::process-job-offset owned) 0)))))
           (is (eq t armed))
           (is (eq t sent))
           (is (null (libtmux.internal::process-job-reason job)))
           (is (equalp #(114 101 97 100 121 10 100 111 110 101 10)
                       (aref (libtmux.internal::process-job-buffers job) 0))))
      (libtmux.internal::cleanup-job job))))

(test control-peer-queues-native-requests-and-delivers-pane-bytes
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (session (aref (libtmux:sessions snapshot) 0))
             (peer nil))
        (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
            (let* ((launched nil)
                   (libtmux.internal::*process-launched-hook*
                     (lambda (job)
                       (when (find "-C" (libtmux.internal::process-job-argv job) :test #'string=)
                         (setf launched t)
                         (error "Control launch reached the old-daemon branch")))))
              (setf (slot-value client 'libtmux::version) "3.8")
              (signals libtmux:unsupported-capability
                (libtmux.internal::start-control-peer client session))
              (signals libtmux:unsupported-capability
                (libtmux.control:open-connection client session))
              (is (null launched)))
            (unwind-protect
                 (progn
                   (setf peer (libtmux.internal::start-control-peer client session :timeout 1))
                   (let ((first (libtmux.internal::submit-control-command
                                 peer '("display-message" "-p" "-l" "first") :effect :read))
                         (second (libtmux.internal::submit-control-command
                                  peer '("display-message" "-p" "-l" "second") :effect :read))
                         (bad (libtmux.internal::submit-control-command
                               peer '("no-such-libtmux-command") :effect :read)))
                     (multiple-value-bind (result delivery)
                         (libtmux.internal::await-control-request first :timeout 1)
                       (is (eq :ready delivery))
                       (is (eq :completed (getf result :status)))
                       (is (equalp #(102 105 114 115 116 10) (getf result :output))))
                     (multiple-value-bind (result delivery)
                         (libtmux.internal::await-control-request second :timeout 1)
                       (is (eq :ready delivery))
                       (is (equalp #(115 101 99 111 110 100 10) (getf result :output))))
                     (multiple-value-bind (result delivery)
                         (libtmux.internal::await-control-request bad :timeout 1)
                       (is (eq :ready delivery))
                       (is (eq :failed (getf result :status)))
                       (is (search "unknown command" (libtmux.internal::decode-utf8 (getf result :output))))))
                   (let ((request (libtmux.internal::submit-control-command
                                   peer '("display-message" "-p" "-l" "after-error") :effect :read)))
                     (is (eq :completed
                             (getf (libtmux.internal::await-control-request request :timeout 1) :status))))
                   (let ((pane (aref (libtmux:panes snapshot) 0))
                         (deadline (+ (libtmux.internal::monotonic-seconds) 1))
                         (bytes (libtmux.internal::byte-buffer)))
                     (is (zerop (nth-value 2 (fixture-command fixture "send-keys" "-t" (libtmux:id pane)
                                                              "-H" "ff" "00" "58" "0a"))))
                     (loop repeat 16
                           for remaining = (- deadline (libtmux.internal::monotonic-seconds))
                           while (plusp remaining)
                           until (search #(255 0 88) bytes)
                           do (multiple-value-bind (event delivery)
                                  (libtmux.internal::next-control-event peer :timeout remaining)
                                (is (eq :ready delivery))
                                (when (eq :output (getf event :kind))
                                  (is (string= (libtmux:id pane) (getf event :pane)))
                                  (let ((data (getf event :data)))
                                    (libtmux.internal::append-bytes bytes data (length data))))))
                     (is (search #(255 0 88) bytes))))
              (when peer (libtmux.internal::close-control-peer peer))))
        (is (zerop (nth-value 2 (fixture-command fixture "has-session"))))))))

(test control-close-retires-pending-work-without-killing-the-daemon
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Persistent control needs tmux 3.8 or newer")
        (let* ((session (aref (libtmux:fetch-sessions client) 0))
               (peer (libtmux.internal::start-control-peer client session :timeout 1)))
          (unwind-protect
               (let* ((active (libtmux.internal::submit-control-command peer '("wait-for" "control-pending") :effect :read))
                      (queued (libtmux.internal::submit-control-command peer '("display-message" "-p" "unused")
                                                                       :effect :read :timeout 0.02)))
                 (is (eq :ready
                         (nth-value 1 (libtmux.internal::wait-control-value
                                       peer (lambda () (libtmux.internal::control-request-dispatched active)) 0.5))))
                 (multiple-value-bind (result delivery) (libtmux.internal::await-control-request queued :timeout 0.5)
                   (is (eq :ready delivery))
                   (is (eq :timed-out (getf result :status)))
                   (is (null (getf result :dispatched-p))))
                 (multiple-value-bind (result delivery) (libtmux.internal::await-control-request active :timeout 0)
                   (is (null result))
                   (is (eq :timeout delivery)))
                 (libtmux.internal::close-control-peer peer)
                 (let ((result (libtmux.internal::await-control-request active :timeout 0)))
                   (is (eq :closed (getf result :status)))
                   (is (eq t (getf result :dispatched-p))))
                 (is (libtmux.internal::control-peer-finished peer))
                 (is (null (libtmux.internal::process-job-pidfd (libtmux.internal::control-peer-job peer))))
                 (is (zerop (nth-value 2 (fixture-command fixture "has-session")))))
            (libtmux.internal::close-control-peer peer)))))))

(test control-startup-error-retains-a-closed-recoverable-peer
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Persistent control needs tmux 3.8 or newer")
        (progn
          (is (zerop (nth-value 2 (fixture-command fixture "new-session" "-d" "-s" "survivor" "/bin/cat"))))
        (let* ((session (aref (libtmux:fetch-sessions client) 0))
               (peer nil)
               (removed nil)
               (libtmux.internal::*before-dispatch-hook*
                 (lambda (job)
                   (when (and (not removed)
                              (find "-C" (libtmux.internal::process-job-argv job) :test #'string=))
                     (setf removed t)
                     (fixture-command fixture "kill-session" "-t" (libtmux:id session))))))
          (unwind-protect
               (progn
                 (handler-case (libtmux.control:open-connection client session :timeout 1)
                   (libtmux.control:connection-start-failed (condition)
                     (let ((connection (libtmux.control:error-connection condition)))
                       (setf peer (libtmux.control::%peer connection))
                       (is (eq connection (libtmux.control::%connection-for-peer peer)))
                       (is (typep (libtmux:error-cause condition) 'libtmux.internal::control-start-failed))
                       (libtmux.control:close-connection connection))))
                 (is (not (null peer)))
                 (when peer
                   (is (libtmux.internal::control-peer-finished peer))
                   (is (null (libtmux.internal::process-job-pidfd (libtmux.internal::control-peer-job peer)))))
                 (is (zerop (nth-value 2 (fixture-command fixture "has-session")))))
            (when peer (libtmux.internal::close-control-peer peer)))))))))

(test control-public-cancellation-is-local-for-queued-work-and-closes-active-work
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Public persistent control needs tmux 3.8 or newer")
          (let* ((session (aref (libtmux:fetch-sessions client) 0))
                 (connection (libtmux.control:open-connection client session :timeout 1)))
            (unwind-protect
                 (let* ((active (libtmux.control:submit-command connection '("wait-for" "public-held") :effect :read))
                        (peer (libtmux.control::%peer connection)))
                   (is (eq :ready
                           (nth-value 1 (libtmux.internal::wait-control-value
                                         peer (lambda () (libtmux.internal::control-request-dispatched
                                                          (libtmux.control::%handle active))) 0.8))))
                   (let ((queued (libtmux.control:submit-command connection '("display-message" "-p" "unused") :effect :read)))
                     (is (libtmux.control:cancel-request queued))
                     (is (eq :cancelled (getf (libtmux.control:await-request queued :timeout 0) :status)))
                     (is (null (getf (libtmux.control:await-request queued :timeout 0) :dispatched-p)))
                     (is (eq :ready (libtmux.control:connection-state connection))))
                   (multiple-value-bind (result delivery) (libtmux.control:await-request active :timeout 0)
                     (is (null result)) (is (eq :timeout delivery)))
                   (let ((unused (libtmux.control:submit-command connection '("display-message" "-p" "never") :effect :read)))
                     (is (libtmux.control:cancel-request active))
                     (let ((result (libtmux.control:await-request active :timeout 0.8)))
                       (is (eq :cancelled (getf result :status)))
                       (is (eq t (getf result :dispatched-p))))
                     (is (eq :closed (getf (libtmux.control:await-request unused :timeout 0.8) :status)))
                     (is (not (libtmux.control:cancel-request active))))
                   (libtmux.control:close-connection connection)
                   (is (eq :closed (libtmux.control:connection-state connection)))
                   (loop repeat 64 for event = (libtmux.control:next-event connection :timeout 0)
                         when (eq :end (getf event :kind))
                           do (is (eq :cancelled (getf event :reason))) (return)
                         finally (fail "No end event after connection cleanup"))
                   (is (zerop (nth-value 2 (fixture-command fixture "has-session")))))
              (libtmux.control:close-connection connection)))))))

(test control-reconnect-recaptures-and-retires-without-replay
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Explicit control reconnect requires tmux 3.8 or newer")
          (let* ((session (aref (libtmux:fetch-sessions client) 0))
                 (generation (getf (libtmux:provenance session) :generation))
                 (old (libtmux.control:open-connection client session :timeout 1
                        :request-limit 3 :event-limit 7 :event-byte-limit 512 :reply-byte-limit 4096))
                 (new nil))
            (unwind-protect
                 (let* ((completed (libtmux.control:submit-command old '("display-message" "-p" "-l" "retained") :effect :read))
                        (before (libtmux.control:await-request completed :timeout 0.8)))
                   (is (eq :completed (getf before :status)))
                   (let* ((active (libtmux.control:submit-command old '("wait-for" "reconnect-held") :effect :read))
                          (peer (libtmux.control::%peer old)))
                     (is (eq :ready
                             (nth-value 1 (libtmux.internal::wait-control-value
                                           peer (lambda () (libtmux.internal::control-request-dispatched
                                                            (libtmux.control::%handle active))) 0.8))))
                     (let ((queued (libtmux.control:submit-command old '("set-option" "-g" "@must-not-replay" "bad")
                                                                 :effect :mutation)))
                       (libtmux.control:with-reconnection (replacement capture old :timeout 1)
                         (setf new replacement)
                         (is (not (eq old new)))
                         (is (eq :closed (libtmux.control:connection-state old)))
                         (is (eq :ready (libtmux.control:connection-state new)))
                         (is (> (getf (libtmux:provenance capture) :generation) generation))
                         (let ((current (find (libtmux:id session) (libtmux:sessions capture)
                                              :key #'libtmux:id :test #'string=)))
                           (is (typep current 'libtmux:session))
                           (is (not (libtmux:same-entity-p session current)))
                           (signals libtmux:stale-target (libtmux:rename-session client session "stale"))
                           (is (eq :succeeded (libtmux:outcome-status
                                              (libtmux:rename-session client current "reconnected" :observe nil)))))
                         (is (eq :closed (getf (libtmux.control:await-request active :timeout 0) :status)))
                         (is (getf (libtmux.control:await-request active :timeout 0) :dispatched-p))
                         (is (eq :closed (getf (libtmux.control:await-request queued :timeout 0) :status)))
                         (is (not (getf (libtmux.control:await-request queued :timeout 0) :dispatched-p)))
                         (is (equalp before (libtmux.control:await-request completed :timeout 0)))
                         (is (not (nth-value 1 (libtmux:show-option client "@must-not-replay" :scope :global-session))))
                         (is (= 3 (libtmux.internal::control-peer-request-limit (libtmux.control::%peer new))))
                         (is (= 7 (libtmux.internal::control-peer-event-limit (libtmux.control::%peer new))))
                         (is (= 512 (libtmux.internal::control-peer-event-byte-limit (libtmux.control::%peer new))))
                         (is (= 4096 (libtmux.internal::control-peer-reply-byte-limit (libtmux.control::%peer new))))
                         (signals libtmux.control:connection-stale (libtmux.control:reconnect old))
                         (let ((read (libtmux.control:submit-command new '("display-message" "-p" "-l" "new") :effect :read)))
                           (is (eq :completed (getf (libtmux.control:await-request read :timeout 0.8) :status))))
                         (loop repeat 128 for event = (libtmux.control:next-event old :timeout 0)
                               when (eq :end (getf event :kind)) return (is (eq :closed (getf event :reason)))
                               finally (fail "Retired connection did not preserve its end event")))))
                   (is (eq :closed (libtmux.control:connection-state new)))
                   (is (string= "reconnected" (libtmux:name (aref (libtmux:fetch-sessions client) 0)))))
              (when new (libtmux.control:close-connection new))
              (libtmux.control:close-connection old)))))))

(defclass cancel-after-control-close (libtmux.control:connection) ())

(defmethod libtmux.control:close-connection :after ((connection cancel-after-control-close))
  (let* ((client (libtmux.internal::control-peer-origin-client (libtmux.control::%peer connection)))
         (operation (slot-value client 'libtmux::active)))
    (when operation (libtmux:cancel (libtmux.internal::operation-token operation)))))

(test control-reconnect-invalidates-before-post-close-cancellation
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Explicit control reconnect requires tmux 3.8 or newer")
          (let* ((session (aref (libtmux:fetch-sessions client) 0))
                 (generation (getf (libtmux:provenance session) :generation))
                 (old (libtmux.control:open-connection client session :timeout 1))
                 (new nil) (launched 0))
            (change-class old 'cancel-after-control-close)
            (unwind-protect
                 (let* ((libtmux.internal::*process-launched-hook*
                          (lambda (job)
                            (when (find "-C" (libtmux.internal::process-job-argv job) :test #'string=)
                              (incf launched))))
                        (failure (handler-case
                                     (progn (setf new (libtmux.control:reconnect old :timeout 1)) nil)
                                   (libtmux:command-cancelled (condition) condition))))
                   (is (typep failure 'libtmux:command-cancelled))
                   (is (zerop launched))
                   (is (> (slot-value client 'libtmux::generation) generation))
                   (is (eq :closed (libtmux.control:connection-state old)))
                   (signals libtmux:stale-target (libtmux:rename-session client session "stale")))
              (when new (libtmux.control:close-connection new))
              (libtmux.control:close-connection old)))))))

(test control-reconnect-refuses-a-new-session-with-the-old-name
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Explicit control reconnect requires tmux 3.8 or newer")
          (let* ((session (aref (libtmux:fetch-sessions client) 0))
                 (old (libtmux.control:open-connection client session :timeout 1))
                 (launched 0))
            (unwind-protect
                 (progn
                   (libtmux:new-session client :name "keep-server" :command '("/bin/cat"))
                   (libtmux:kill-session client session)
                   (let* ((outcome (libtmux:new-session client :name "fixture" :command '("/bin/cat")))
                          (replacement (libtmux:outcome-value outcome)))
                     (is (not (string= (libtmux:id session) (libtmux:id replacement))))
                     (is (string= (libtmux:name session) (libtmux:name replacement))))
                   (let ((libtmux.internal::*process-launched-hook*
                           (lambda (job)
                             (when (find "-C" (libtmux.internal::process-job-argv job) :test #'string=)
                               (incf launched)))))
                     (signals libtmux.control:connection-stale (libtmux.control:reconnect old :timeout 1)))
                   (is (zerop launched))
                   (is (libtmux:client-open-p client)))
              (libtmux.control:close-connection old)))))))

(defclass refusing-control-close (libtmux.control:connection)
  ((refuse :initform t)))

(defmethod libtmux.control:close-connection ((connection refusing-control-close))
  (if (slot-value connection 'refuse)
      (error 'libtmux.control:connection-cleanup-failed :connection connection :resource connection
             :message "Fixture refused control close")
      (call-next-method)))

(test control-reconnect-retains-a-generic-close-failure
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Explicit control reconnect requires tmux 3.8 or newer")
          (let* ((session (aref (libtmux:fetch-sessions client) 0))
                 (generation (getf (libtmux:provenance session) :generation))
                 (old (libtmux.control:open-connection client session :timeout 1))
                 (launched 0))
            (change-class old 'refusing-control-close)
            (unwind-protect
                 (let* ((libtmux.internal::*process-launched-hook*
                          (lambda (job)
                            (when (find "-C" (libtmux.internal::process-job-argv job) :test #'string=)
                              (incf launched))))
                        (failure (handler-case (progn (libtmux.control:reconnect old :timeout 1) nil)
                                   (libtmux.control:connection-cleanup-failed (condition) condition))))
                   (is (typep failure 'libtmux.control:connection-cleanup-failed))
                   (is (eq old (libtmux.control:error-connection failure)))
                   (is (= generation (slot-value client 'libtmux::generation)))
                   (is (eq :ready (libtmux.control:connection-state old)))
                   (is (libtmux:client-open-p client))
                   (is (zerop launched))
                   (is (plusp (length (libtmux.control:connection-cleanup-failures old))))
                   (is (find old (libtmux.control:pending-cleanups)))
                   (when (plusp (length (libtmux.control:connection-cleanup-failures old)))
                     (is (eq failure (aref (libtmux.control:connection-cleanup-failures old) 0)))))
              (setf (slot-value old 'refuse) nil)
              (libtmux.control:close-connection old)))))))

(test control-startup-cancellation-retains-its-cause
  (with-tmux-fixture (fixture)
    (libtmux:with-client (client :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                 :socket-path (fixture-socket fixture))
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8"))
          (skip "Persistent control startup requires tmux 3.8 or newer")
          (let* ((session (aref (libtmux:fetch-sessions client) 0))
                 (libtmux.internal::*process-launched-hook*
                   (lambda (job)
                     (when (find "-C" (libtmux.internal::process-job-argv job) :test #'string=)
                       (libtmux:cancel (libtmux.internal::process-job-token job)))))
                 (failure (handler-case
                              (progn (libtmux.control:open-connection client session :timeout 1) nil)
                            (libtmux.control:connection-start-failed (condition) condition))))
            (is (typep failure 'libtmux.control:connection-start-failed))
            (let ((candidate (libtmux.control:error-connection failure)))
              (unwind-protect
                   (progn
                     (is (typep (libtmux:error-cause (libtmux:error-cause failure)) 'libtmux:command-cancelled))
                     (is (eq :closed (libtmux.control:connection-state candidate)))
                     (is (libtmux:client-open-p client)))
                (libtmux.control:close-connection candidate))))))))
