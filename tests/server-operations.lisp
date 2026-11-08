(in-package #:libtmux.tests)

(in-suite integration)

(test server-access-entry-lifecycle-and-client-flags
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((account (sb-posix:getpwnam "nobody"))
             (user (sb-posix:passwd-name account))
             (group (sb-posix:group-name (sb-posix:getgrgid (sb-posix:passwd-gid account))))
             (owner (sb-posix:passwd-name (sb-posix:getpwuid (sb-posix:getuid))))
             (modern (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8")))
        (when (member (sb-posix:passwd-uid account) (list 0 (sb-posix:getuid)))
          (error "The ACL fixture needs nobody to be a non-owner account"))
        (labels ((entry (access &optional group-p)
                   (format nil "~A (~A~A)" (if group-p group user)
                           (if modern (if group-p "G," "U,") "") access))
                 (listed (text) (search text (libtmux:list-server-access client))))
          (multiple-value-bind (text outcome) (libtmux:list-server-access client)
            (is (stringp text))
            (is (eq :succeeded (libtmux:outcome-status outcome))))
          (is (eq :succeeded (libtmux:outcome-status (libtmux:server-access client user :allow))))
          (is (listed (entry "W")))
          (signals libtmux:command-failed (libtmux:server-access client user :allow))
          (libtmux:server-access client user :read-only)
          (is (listed (entry "R")))
          (call-with-attached-terminal-client
           fixture
           (lambda (terminal)
             (declare (ignore terminal))
             (let ((name (string-right-trim '(#\Newline)
                                           (fixture-ok fixture "list-clients" "-F" "#{client_name}"))))
               (fixture-ok fixture "refresh-client" "-t" name "-f" "read-only")
               (is (equal (format nil "1~%")
                          (fixture-ok fixture "display-message" "-c" name "-p" "#{client_readonly}")))
               (libtmux:server-access client user :read-write)
               (is (listed (entry "W")))
               ;; In 3.8 an unrelated ACL update recomputes the owner's flags.
               (is (equal (format nil "~D~%" (if modern 0 1))
                          (fixture-ok fixture "display-message" "-c" name "-p" "#{client_readonly}"))))))
          (libtmux:server-access client user :deny)
          (is (not (listed (entry "W"))))
          (signals libtmux:command-failed (libtmux:server-access client user :deny))
          (libtmux:server-access client user :read-only)
          (is (listed (entry "R")))
          (signals libtmux:command-failed (libtmux:server-access client owner :read-only))
          (signals libtmux:command-failed (libtmux:server-access client "root" :allow))
          (handler-case
              (progn (libtmux:server-access client "libtmux-no-account-#{pid}" :allow)
                     (fail "An unknown literal account succeeded"))
            (libtmux:command-failed (condition)
              (is (search "libtmux-no-account-#{pid}"
                          (libtmux.internal::strict-text
                           (libtmux:outcome-stderr (libtmux:error-outcome condition)))))))
          (if modern
              (progn
                (libtmux:server-access client group :read-write :group-p t)
                (is (listed (entry "W" t)))
                (is (listed (entry "R")))
                (signals libtmux:command-failed (libtmux:server-access client group :allow :group-p t))
                (libtmux:server-access client group :read-only :group-p t)
                (is (listed (entry "R" t)))
                (libtmux:server-access client group :deny :group-p t)
                (is (not (listed (entry "R" t)))))
              (handler-case
                  (progn (libtmux:server-access client group :allow :group-p t)
                         (fail "An older daemon admitted a group ACL operation"))
                (libtmux:unsupported-capability (condition)
                  (is (eq :not-dispatched
                          (libtmux:outcome-status (libtmux:error-outcome condition)))))))
          (libtmux:server-access client user :deny))))))

(test display-message-preserves-literals-formats-and-link-context
  (with-tmux-fixture (fixture)
    (fixture-ok fixture "link-window" "-s" "@0" "-t" "fixture:3")
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (session (aref (libtmux:sessions snapshot) 0))
             (window (aref (libtmux:windows snapshot) 0))
             (pane (aref (libtmux:panes snapshot) 0))
             (text (format nil "-λ'\";#{pid};#(false);#[one]##[#{pid}];%Y;%%;\\~%  ~Ctail~%" #\Tab)))
        (multiple-value-bind (printed outcome) (libtmux:display-message client text)
          (is (equal (format nil "~A~%" text) printed))
          (is (eq :succeeded (libtmux:outcome-status outcome)))
          (is (equalp (libtmux.internal::encode-utf8 printed) (libtmux:outcome-stdout outcome))))
        (is (equal (string #\Newline) (libtmux:display-message client "")))
        (loop for target in (list session window pane)
              for field in '("session_id" "window_id" "pane_id")
              do (is (equal (format nil "~A|%~%" (libtmux:id target))
                            (libtmux:display-message client (format nil "#{~A}|%%" field)
                                                     :target target :format-p t))))
        (loop for link across (libtmux:window-links snapshot)
              do (destructuring-bind (session-id index window-id) (libtmux:id link)
                   (is (equal (format nil "~A:~D:~A~%" session-id index window-id)
                              (libtmux:display-message
                               client "#{session_id}:#{window_index}:#{window_id}"
                               :target link :format-p t)))))
        (with-fixture-client (other fixture)
          (signals libtmux:stale-target
            (libtmux:display-message other "text" :target pane)))
        (let ((large (make-string 8192 :initial-element #\a)))
          (if (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.4")
              (is (equal (format nil "~A~%" large) (libtmux:display-message client large)))
              (handler-case
                  (progn (libtmux:display-message client large)
                         (fail "The floor literal fallback admitted an oversized intermediate"))
                (libtmux:invalid-argument (condition)
                  (is (eq :not-dispatched
                          (libtmux:outcome-status (libtmux:error-outcome condition))))))))
        ;; Hooks share the ordinary printer; preserve their output as text.
        (fixture-ok fixture "set-hook" "-g" "after-display-message"
                    "list-commands -F hook-output list-sessions")
        (is (equal (format nil "text~%hook-output~%")
                   (libtmux:display-message client "text" :target pane)))))))

(defclass wait-readiness-transport (libtmux.internal::subprocess-transport)
  ((channel :initarg :channel)))

(defmethod libtmux.internal::execute-command :around
    ((transport wait-readiness-transport) argv &key input timeout output-limit cancel-token keep-input-open)
  (let ((guard (position "if-shell" argv :test #'equal)))
    (if guard
        (let ((prepared (copy-list argv)))
          ;; The same server queue reaches WAIT before servicing readiness.
          (setf (nth (+ guard 3) prepared)
                (concatenate 'string
                             (libtmux.internal::tmux-command-text
                              (list "wait-for" "-S" (slot-value transport 'channel)))
                             " ; " (nth (+ guard 3) prepared)))
          (call-next-method transport prepared :input input :timeout timeout
                                              :output-limit output-limit :cancel-token cancel-token
                                              :keep-input-open keep-input-open))
        (call-next-method))))

(defun exercise-queued-channel-request (client fixture channel operation &optional action)
  (let* ((nonce (format nil "~36R" (random (ash 1 128))))
         (ready (concatenate 'string "queued-" nonce))
         (program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux"))
         (token (libtmux:make-cancellation-token))
         (original (slot-value client 'libtmux::transport))
         (worker nil) (failure nil) (result nil))
    (unwind-protect
         (progn
           (setf (slot-value client 'libtmux::transport)
                 (make-instance 'wait-readiness-transport :channel ready)
                 worker
                 (sb-thread:make-thread
                  (lambda ()
                    (handler-case
                        (setf result (libtmux:wait-for client channel :operation operation
                                                      :cancel-token token))
                      (error (condition) (setf failure condition))))))
           (unless (eq :succeeded
                       (libtmux:outcome-status
                        (libtmux.internal::run-process
                         (list program "-N" "-S" (fixture-socket fixture) "wait-for" ready)
                         :timeout 0.5)))
             (error "Owned wait request did not report readiness"))
           (is (= 1 (count #\Newline (fixture-ok fixture "wait-for" "-l" channel))))
           (if action (funcall action) (libtmux:cancel token))
           (sb-thread:join-thread worker :timeout 0.75)
           (if action
               (progn (is (null failure))
                      (is (eq :succeeded (libtmux:outcome-status result))))
               (progn (is (typep failure 'libtmux:command-cancelled))
                      (is (eq :unknown (libtmux:outcome-status (libtmux:error-outcome failure))))))
           ;; Observe disposal directly; CLI join is not a daemon EOF barrier.
           (is (equal "" (fixture-ok fixture "wait-for" "-l" channel))))
      (libtmux:cancel token)
      (when worker (sb-thread:join-thread worker :timeout 0.75))
      (setf (slot-value client 'libtmux::transport) original))))

(test wait-channel-literals-and-version-gates
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((channel (format nil "-literal-#{pid};λ'\"~%channel"))
            (program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")))
        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:wait-for client channel :operation :signal))))
        (is (eq :succeeded
                (libtmux:outcome-status
                 (libtmux.internal::run-process
                  (list program "-N" "-S" (fixture-socket fixture) "wait-for" "--" channel)
                  :timeout 0.5))))
        (unless (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8")
          (dolist (operation '(:wait :lock))
            (handler-case
                (progn (libtmux:wait-for client channel :operation operation)
                       (fail "An older daemon admitted a blocking channel request"))
              (libtmux:unsupported-capability (condition)
                (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))
                (is (equal "3.8" (libtmux:error-required-version condition)))))))
        (signals libtmux:command-failed
          (libtmux:wait-for client "not-locked" :operation :unlock))))))

(test wait-channel-cancellation-removes-queued-waiters-without-unlocking
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (when (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8")
        (libtmux:wait-for client "ready" :operation :signal)
        (is (eq :succeeded (libtmux:outcome-status (libtmux:wait-for client "ready"))))
        ;; Two signals remove the pending wake. The following wait must queue.
        (libtmux:wait-for client "ready" :operation :signal)
        (libtmux:wait-for client "ready" :operation :signal)
        (exercise-queued-channel-request client fixture "ready" :wait)
        (with-fixture-client (signaller fixture)
          (exercise-queued-channel-request
           client fixture "ready" :wait
           (lambda () (libtmux:wait-for signaller "ready" :operation :signal))))
        ;; A lost reply and closing the initiating client do not release a lock.
        (with-fixture-client (holder fixture)
          (setf (slot-value holder 'libtmux::transport)
                (make-instance 'receipt-loss-transport :keep-entry t))
          (signals libtmux:outcome-unknown
            (libtmux:wait-for holder "lock" :operation :lock)))
        (exercise-queued-channel-request client fixture "lock" :lock)
        (with-fixture-client (signaller fixture)
          (exercise-queued-channel-request
           client fixture "lock" :lock
           (lambda () (libtmux:wait-for signaller "lock" :operation :unlock))))
        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:wait-for client "lock" :operation :unlock))))
        (is (eq :succeeded
                (libtmux:outcome-status (libtmux:wait-for client "lock" :operation :lock))))
        (libtmux:wait-for client "lock" :operation :unlock)))))
