(in-package #:libtmux.tests)

(in-suite control-integration)

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
        (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.7"))
            (let* ((launched nil)
                   (libtmux.internal::*process-launched-hook*
                     (lambda (job)
                       (when (find "-C" (libtmux.internal::process-job-argv job) :test #'string=)
                         (setf launched t)
                         (error "Control launch reached the old-daemon branch")))))
              (setf (slot-value client 'libtmux::version) "3.8")
              (signals libtmux:unsupported-capability
                (libtmux.internal::start-control-peer client session))
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
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.7"))
          (skip "Persistent control needs tmux 3.7 or newer")
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
      (if (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.7"))
          (skip "Persistent control needs tmux 3.7 or newer")
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
                 (handler-case (libtmux.internal::start-control-peer client session :timeout 1)
                   (libtmux.internal::control-start-failed (condition)
                     (setf peer (libtmux.internal::failed-control-peer condition))))
                 (is (not (null peer)))
                 (when peer
                   (is (libtmux.internal::control-peer-finished peer))
                   (is (null (libtmux.internal::process-job-pidfd (libtmux.internal::control-peer-job peer)))))
                 (is (zerop (nth-value 2 (fixture-command fixture "has-session")))))
            (when peer (libtmux.internal::close-control-peer peer)))))))))
