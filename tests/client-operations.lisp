(in-package #:libtmux.tests)

(in-suite integration)

(defun terminal-observation (client terminal)
  (or (find (sb-ext:process-pid (terminal-client-process terminal))
            (libtmux:fetch-clients client)
            :key (lambda (value) (libtmux:field-value value :client/pid)))
      (error "Owned terminal client was not captured")))

(test attached-client-switch-refresh-detach-and-authority
  (with-tmux-fixture (fixture)
    (fixture-ok fixture "new-session" "-d" "-s" "second" "/bin/cat")
    (fixture-ok fixture "set-option" "-t" "second" "update-environment"
                "LIBTMUX_CLIENT_PROBE")
    (fixture-ok fixture "set-environment" "-t" "second" "LIBTMUX_CLIENT_PROBE" "retained")
    (with-fixture-client (client fixture)
      (call-with-attached-terminal-client
       fixture
       (lambda (first)
         (call-with-attached-terminal-client
          fixture
          (lambda (second)
            (let* ((target (terminal-observation client first))
                   (sibling (terminal-observation client second))
                   (destination (find "second" (libtmux:fetch-sessions client)
                                      :key #'libtmux:name :test #'string=))
                   (outcome (libtmux:switch-client client target destination)))
              (is (eq :succeeded (libtmux:outcome-status outcome)))
              (is (equal "second" (libtmux:name (libtmux:session (libtmux:outcome-value outcome)))))
              (is (equal "fixture" (libtmux:name (libtmux:session target))))
              (is (equal "fixture" (libtmux:name (libtmux:session (libtmux:refresh client sibling)))))
              (is (equal (format nil "LIBTMUX_CLIENT_PROBE=retained~%")
                         (fixture-ok fixture "show-environment" "-t" "second" "LIBTMUX_CLIENT_PROBE")))
              (libtmux:switch-client client target destination :update-environment t :observe nil)
              (is (equal (format nil "-LIBTMUX_CLIENT_PROBE~%")
                         (fixture-ok fixture "show-environment" "-t" "second" "LIBTMUX_CLIENT_PROBE")))
              (fixture-ok fixture "set-hook" "-g" "after-refresh-client"
                          "set-option -gF @refresh-request '#{hook_flag_t}|#{hook_flag_S}'")
              (dolist (status-only '(nil t))
                (is (eq :succeeded
                        (libtmux:outcome-status
                         (libtmux:refresh-client client target :status-only status-only))))
                (is (equal (format nil "~A:|~A~%" (libtmux:name target) (if status-only "1" ""))
                           (fixture-ok fixture "show-options" "-gv" "@refresh-request"))))
              (with-fixture-client (foreign fixture)
                (let* ((calls 0)
                       (libtmux.internal::*process-started-hook*
                         (lambda (process) (declare (ignore process)) (incf calls))))
                  (signals libtmux:stale-target (libtmux:detach-client foreign target))
                  (is (zerop calls))))
              (is (eq :succeeded (libtmux:outcome-status (libtmux:detach-client client target))))
              (is (sb-sys:wait-until-fd-usable (terminal-client-pidfd first) :input 0.5))
              (is (sb-ext:process-alive-p (terminal-client-process second)))
              (handler-case
                  (progn (libtmux:detach-client client target) (fail "Detached client was reused"))
                (libtmux:stale-target (condition)
                  (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))))
              (is (= 1 (length (libtmux:fetch-clients client))))
              (setf (slot-value client 'libtmux::transport)
                    (make-instance 'receipt-loss-transport :keep-entry t))
              (handler-case
                  (progn (libtmux:detach-client client sibling)
                         (fail "A detach without its completion receipt became success"))
                (libtmux:outcome-unknown (condition)
                  (is (eq :unknown (libtmux:outcome-status (libtmux:error-outcome condition))))
                  (is (eq :missing-completion-receipt
                          (libtmux:outcome-reason (libtmux:error-outcome condition))))))
              (is (sb-sys:wait-until-fd-usable (terminal-client-pidfd second) :input 0.5))))))))))

(test attached-client-suspend-is-a-native-job-control-request
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((owned nil))
        (call-with-attached-terminal-client
         fixture
         (lambda (terminal)
           (setf owned terminal)
           (let ((target (terminal-observation client terminal)))
             (is (eq :succeeded (libtmux:outcome-status (libtmux:suspend-client client target))))
             (is (wait-terminal-status terminal '(:stopped)))
             (is (= sb-posix:sigtstp (sb-ext:process-exit-code (terminal-client-process terminal))))
             (is (zerop (libtmux.internal::pidfd-signal (terminal-client-pidfd terminal)
                                                       sb-posix:sigcont (sb-sys:int-sap 0) 0)))
             (is (wait-terminal-status terminal '(:running)))
             (is (= (sb-ext:process-pid (terminal-client-process terminal))
                    (libtmux:field-value (libtmux:refresh client target) :client/pid))))))
        (is (null (terminal-client-cleanup-failures owned)))
        (is (member (sb-ext:process-status (terminal-client-process owned)) '(:exited :signaled)))))))

(defun call-with-lock-program (fixture session function)
  (let* ((nonce (format nil "lock-~A" (gensym)))
         (ready-path (namestring (merge-pathnames (concatenate 'string nonce "-ready")
                                                 (fixture-directory fixture))))
         (release-path (namestring (merge-pathnames (concatenate 'string nonce "-release")
                                                   (fixture-directory fixture))))
         (ready nil) (release nil) (lock-pidfd nil))
    (unwind-protect
         (progn
           (sb-posix:mkfifo ready-path #o600)
           (sb-posix:mkfifo release-path #o600)
           (setf ready (sb-posix:open ready-path (logior sb-posix:o-rdwr sb-posix:o-nonblock))
                 release (sb-posix:open release-path (logior sb-posix:o-rdwr sb-posix:o-nonblock)))
           (fixture-ok fixture "set-option" "-t" session "lock-command"
                       (format nil "exec /bin/bash -c 'exec 3<>\"~A\"; printf \"%s\\n\" \"$$\" > \"~A\"; read -r -t 0.75 release <&3'"
                               release-path ready-path))
           (funcall function
                    (lambda ()
                      (unless (sb-sys:wait-until-fd-usable ready :input 0.5)
                        (error "Owned lock command did not report readiness"))
                      (let* ((buffer (make-array 64 :element-type '(unsigned-byte 8)))
                             (length (sb-sys:with-pinned-objects (buffer)
                                       (sb-posix:read ready (sb-sys:vector-sap buffer) (length buffer))))
                             (pid (parse-integer (libtmux.internal::strict-text (subseq buffer 0 length)))))
                        (setf lock-pidfd (fixture-pidfd-open pid 0))
                        (is (>= lock-pidfd 0))
                        (is (not (sb-sys:wait-until-fd-usable lock-pidfd :input 0)))))))
      ;; Retire the shell before the enclosing terminal scope can close.
      (unwind-protect
           (progn
             (when release
               (libtmux.internal::raw-write release (libtmux.internal::octet-vector #(120 10))))
             (when (and lock-pidfd (>= lock-pidfd 0))
               (unless (sb-sys:wait-until-fd-usable lock-pidfd :input 0.5)
                 (error "Owned lock command did not exit after release"))))
        (when (and lock-pidfd (>= lock-pidfd 0)) (sb-posix:close lock-pidfd))
        (when ready (sb-posix:close ready))
        (when release (sb-posix:close release))))))

(test attached-client-lock-executes-and-releases-the-owned-lock-command
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (call-with-attached-terminal-client
       fixture
       (lambda (terminal)
         (call-with-lock-program
          fixture "fixture"
          (lambda (await)
            (is (eq :succeeded
                    (libtmux:outcome-status
                     (libtmux:lock-client client (terminal-observation client terminal)))))
            (funcall await))))))))

(test session-and-server-locks-respect-live-membership
  (dolist (scope '(:session :server))
    (with-tmux-fixture (fixture)
      (fixture-ok fixture "new-session" "-d" "-s" "second" "/bin/cat")
      (with-fixture-client (client fixture)
        (is (eq :succeeded (libtmux:outcome-status (libtmux:lock-server client))))
        (call-with-attached-terminal-client
         fixture
         (lambda (first)
           (call-with-attached-terminal-client
            fixture
            (lambda (second)
              (let* ((snapshot (libtmux:fetch-snapshot client))
                     (sessions (libtmux:sessions snapshot))
                     (target (find "fixture" sessions :key #'libtmux:name :test #'string=))
                     (other (find "second" sessions :key #'libtmux:name :test #'string=))
                     (first-target (terminal-observation client first))
                     (second-target (terminal-observation client second)))
                (libtmux:switch-client client second-target other :observe nil)
                (with-fixture-client (foreign fixture)
                  (signals libtmux:stale-target (libtmux:lock-session foreign target)))
                (call-with-lock-program
                 fixture "fixture"
                 (lambda (await-first)
                   (call-with-lock-program
                    fixture "second"
                    (lambda (await-second)
                      (is (eq :succeeded
                              (libtmux:outcome-status
                               (ecase scope
                                 (:session (libtmux:lock-session client target))
                                 (:server (libtmux:lock-server client))))))
                      ;; Newer list-clients omits suspended clients; address each directly.
                      (dolist (expected (list (list first-target target t)
                                             (list second-target other (eq scope :server))))
                        (destructuring-bind (observation session suspended-p) expected
                          (let* ((prefix (format nil "~D " (libtmux:field-value observation :client/pid)))
                                 (row (fixture-ok
                                       fixture "display-message" "-p"
                                       "-c" (concatenate 'string (libtmux:name observation) ":")
                                       "-t" (concatenate 'string (libtmux:id session) ":")
                                       "#{client_pid} #{client_flags}")))
                            (is (uiop:string-prefix-p prefix row))
                            (is (eq (not (null (search "suspended" row))) suspended-p)))))
                      (funcall await-first)
                      (when (eq scope :server) (funcall await-second)))))))))))))))
