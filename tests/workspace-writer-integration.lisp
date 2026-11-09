(in-package #:libtmux.tests)

(in-suite workspace-writer-integration)

(defun writer-token (character) (make-string 32 :initial-element character))

(defun prepare-fixture-writer (client &key state declaration (token #\B))
  (let* ((declaration (or declaration (state-fixture-declaration "new-owned" "writer")))
         (state (or state (state-call :fetch-owned-state client declaration))))
    (state-call :prepare-owned-writer client declaration state :writer-token (writer-token token))))

(defun writer-failure (function)
  (handler-case (progn (funcall function) (error "Invalid writer progress was accepted"))
    (libtmux.workspace::owned-writer-error (condition) condition)))

(test owned-writer-genesis-claims-and-writes-immutable-pending-without-domain-effects
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((writer (prepare-fixture-writer client))
             (control "@libtmux.workspace.777269746572.control"))
        (state-call :claim-owned-writer writer)
        (is (eq :claimed (getf (state-call :owned-writer-data writer) :stage)))
        (state-call :retire-owned-writer-records writer)
        (let ((record (state-call :write-owned-writer-pending writer)))
          (is (equal "0" (getf (state-call :owned-record-data record) :base))))
        (is (eq :pending (getf (state-call :owned-writer-data writer) :stage)))
        (is (string= (state-call :make-owned-control :busy "0" (writer-token #\B))
                     (string-right-trim '(#\Newline) (fixture-ok fixture "show-options" "-s" "-v" control))))
        (is (= 1 (length (libtmux:sessions (libtmux:fetch-snapshot client)))))
        (let ((libtmux.internal::*process-launched-hook*
                (lambda (job) (declare (ignore job)) (error "Writer inspection performed I/O"))))
          (let ((data (state-call :owned-writer-data writer)))
            (setf (char (getf data :control) 0) #\X)
            (is (char= #\W (char (getf (state-call :owned-writer-data writer) :control) 0)))
            (is (plusp (length (state-call :owned-writer-outcomes writer))))))))))

(test owned-writer-contention-refuses-without-stealing-or-retrying
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (dolist (existing '(nil t))
        (let* ((declaration (if existing (install-state-fixture fixture client)
                                (state-fixture-declaration "new-owned" "writer")))
               (state (state-call :fetch-owned-state client declaration))
               (first (prepare-fixture-writer client :state state :declaration declaration :token #\B))
               (second (prepare-fixture-writer client :state state :declaration declaration :token #\C)))
          (state-call :claim-owned-writer first)
          (let ((failure (writer-failure (lambda () (state-call :claim-owned-writer second)))))
            (is (typep (libtmux:error-cause failure) 'libtmux:libtmux-error))
            (is (eq :failed (getf (state-call :owned-writer-data second) :stage)))
            (let ((outcomes (state-call :owned-writer-outcomes second)))
              (is (= 1 (length outcomes)))
              (is (not (eq :succeeded (libtmux:outcome-status (aref outcomes 0)))))))
          (is (search (writer-token #\B)
                      (fixture-ok fixture "show-options" "-s" "-v"
                                  (getf (state-call :owned-writer-data first) :control-key)))))))))

(test owned-writer-retirement-preserves-current-and-unknown-keys
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (writer (prepare-fixture-writer client :declaration declaration))
             (revision (writer-token #\A))
             (descriptor (state-call :owned-record-key "acquisition" :committed revision))
             (pending (state-call :owned-record-key "acquisition" :pending revision)))
        (state-call :claim-owned-writer writer)
        (fixture-ok fixture "set-option" "-s" "-u" "--"
                    (state-call :owned-record-key "acquisition" :pending revision 0))
        (fixture-ok fixture "set-option" "-s" "--" "@libtmux.workspace.6163717569736974696F6E.unknown" "keep")
        (state-call :retire-owned-writer-records writer)
        (is (eq :retired (getf (state-call :owned-writer-data writer) :stage)))
        (is (plusp (length (fixture-ok fixture "show-options" "-s" "-v" descriptor))))
        (is (string= (format nil "keep~%")
                     (fixture-ok fixture "show-options" "-s" "-v" "@libtmux.workspace.6163717569736974696F6E.unknown")))
        (is (not (search pending (fixture-ok fixture "show-options" "-s"))))))))

(test owned-writer-chunk-collision-retains-partial-outcomes-and-stops
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((data (state-call :owned-declaration-data (state-fixture-declaration "new-owned" "writer")))
             (pane (aref (getf (aref (getf (getf data :session) :windows) 0) :panes) 0))
             (declaration (progn (setf (getf pane :command) (vector "/bin/cat" (make-string 3000 :initial-element #\a)))
                                 (state-call :make-owned-declaration data)))
             (writer (prepare-fixture-writer client :declaration declaration))
             (revision (writer-token #\B))
             (chunk (state-call :owned-record-key "writer" :pending revision 1))
             (descriptor (state-call :owned-record-key "writer" :pending revision)))
        (state-call :claim-owned-writer writer)
        (state-call :retire-owned-writer-records writer)
        (fixture-ok fixture "set-option" "-s" "--" chunk "collision")
        (writer-failure (lambda () (state-call :write-owned-writer-pending writer)))
        (is (plusp (length (fixture-ok fixture "show-options" "-s" "-v"
                                      (state-call :owned-record-key "writer" :pending revision 0)))))
        (is (string= (format nil "collision~%") (fixture-ok fixture "show-options" "-s" "-v" chunk)))
        (is (not (search descriptor (fixture-ok fixture "show-options" "-s"))))
        (is (some (lambda (outcome) (eq :succeeded (libtmux:outcome-status outcome)))
                  (state-call :owned-writer-outcomes writer)))
        (signals libtmux.workspace:workspace-error (state-call :claim-owned-writer writer))))))

(test owned-writer-original-context-is-checked-after-preflight
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((writer (prepare-fixture-writer client))
             (replaced nil)
             (libtmux.internal::*process-launched-hook*
               (lambda (job)
                 (declare (ignore job))
                 (unless replaced
                   (setf replaced t)
                   (fixture-ok fixture "kill-server")
                   (fixture-ok fixture "new-session" "-d" "-s" "replacement" "/bin/cat")))))
        (let ((failure (writer-failure (lambda () (state-call :claim-owned-writer writer)))))
          (is-true replaced)
          (is (typep (libtmux:error-cause failure) 'libtmux:stale-target))
          (is (every (lambda (outcome) (eq :not-dispatched (libtmux:outcome-status outcome)))
                     (state-call :owned-writer-outcomes writer)))
          (is (not (search "@libtmux.workspace." (fixture-ok fixture "show-options" "-s")))))))))

(test owned-writer-readback-failure-keeps-successful-claim-separate
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((writer (prepare-fixture-writer client))
             (key (getf (state-call :owned-writer-data writer) :control-key))
             (changed nil)
             (libtmux.internal::*process-launched-hook*
               (lambda (job)
                 (when (and (not changed)
                            (some (lambda (argument) (and (search "show-options" argument) (search key argument)))
                                  (libtmux.internal::process-job-argv job)))
                   (setf changed t)
                   (fixture-ok fixture "set-option" "-s" "--" key
                               (state-call :make-owned-control :busy "0" (writer-token #\C)))))))
        (writer-failure (lambda () (state-call :claim-owned-writer writer)))
        (is-true changed)
        (is (eq :succeeded (libtmux:outcome-status (aref (state-call :owned-writer-outcomes writer) 0))))
        (is (eq :failed (getf (state-call :owned-writer-data writer) :stage)))
        (is (search (writer-token #\C) (fixture-ok fixture "show-options" "-s" "-v" key)))))))

(test owned-writer-nonlocal-exit-never-leaves-a-reusable-writer
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((writer (prepare-fixture-writer client)))
        (is (eq :interrupted
                (catch 'writer-exit
                  (let ((libtmux.internal::*process-launched-hook*
                          (lambda (job) (declare (ignore job)) (throw 'writer-exit :interrupted))))
                    (state-call :claim-owned-writer writer)))))
        (is (eq :failed (getf (state-call :owned-writer-data writer) :stage)))
        (let ((libtmux.internal::*process-launched-hook*
                (lambda (job) (declare (ignore job)) (error "An interrupted writer was reused"))))
          (signals libtmux.workspace:workspace-error (state-call :claim-owned-writer writer)))))))

(test owned-writer-retirement-rechecks-the-token-adjacent-to-deletion
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (writer (prepare-fixture-writer client :declaration declaration))
             (key (state-call :owned-record-key "acquisition" :pending (writer-token #\A) 0))
             (control (getf (state-call :owned-writer-data writer) :control-key))
             (changed nil))
        (state-call :claim-owned-writer writer)
        (let ((libtmux.internal::*process-launched-hook*
                (lambda (job)
                  (when (and (not changed)
                             (some (lambda (argument) (and (search "set-option" argument) (search "-u" argument)
                                                           (search key argument)))
                                   (libtmux.internal::process-job-argv job)))
                    (setf changed t)
                    (fixture-ok fixture "set-option" "-s" "--" control
                                (state-call :make-owned-control :busy (writer-token #\A) (writer-token #\C)))))))
          (let ((failure (writer-failure (lambda () (state-call :retire-owned-writer-records writer)))))
            (is (typep (libtmux:error-cause failure) 'libtmux.internal::dispatch-precondition-failed))))
        (is-true changed)
        (is (plusp (length (fixture-ok fixture "show-options" "-s" "-v" key))))))))

(test owned-writer-unknown-claim-outcome-never-triggers-readback-or-replay
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((writer (prepare-fixture-writer client))
             (original (symbol-function 'libtmux.internal::perform-command)) (calls 0))
        (unwind-protect
             (progn
               (setf (symbol-function 'libtmux.internal::perform-command)
                     (lambda (&rest arguments)
                       (incf calls)
                       (let ((outcome (apply original arguments)))
                         (setf (slot-value outcome 'libtmux::status) :unknown
                               (slot-value outcome 'libtmux::reason) :injected-uncertainty)
                         (error 'libtmux:outcome-unknown :outcome outcome :message "Injected uncertain receipt"))))
               (let ((failure (writer-failure (lambda () (state-call :claim-owned-writer writer)))))
                 (is (typep (libtmux:error-cause failure) 'libtmux:outcome-unknown))
                 (is (= 1 (length (state-call :owned-writer-outcomes writer))))))
          (setf (symbol-function 'libtmux.internal::perform-command) original))
        (is (= 1 calls))
        (is (eq :unknown (libtmux:outcome-status (aref (state-call :owned-writer-outcomes writer) 0))))))))

(test owned-writer-total-admission-deadline-retains-completed-claims
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((writer (prepare-fixture-writer client)))
        (state-call :claim-owned-writer writer)
        (let ((before (state-call :owned-writer-outcomes writer))
              (libtmux.internal::*process-launched-hook*
                (lambda (job) (declare (ignore job)) (error "Expired writer admitted I/O"))))
          (setf (slot-value writer 'libtmux.workspace::deadline) (1- (libtmux.internal::monotonic-seconds)))
          (let ((failure (writer-failure (lambda () (state-call :retire-owned-writer-records writer)))))
            (is (typep (libtmux:error-cause failure) 'libtmux.workspace:workspace-deadline-exceeded))
            (is (not (typep (libtmux:error-cause failure) 'libtmux:outcome-unknown)))
            (is (equalp before (state-call :owned-writer-outcomes writer)))))))))

(test owned-writer-nonlocal-read-exit-retains-the-completed-ledger
  (dolist (scenario '(:preflight :closing-control))
    (with-tmux-fixture (fixture)
      (with-fixture-client (client fixture)
        (let* ((declaration (install-state-fixture fixture client))
               (writer (prepare-fixture-writer client :declaration declaration))
               (key (getf (state-call :owned-writer-data writer) :control-key))
               (launches 0) (controls 0))
          (state-call :claim-owned-writer writer)
          (let ((before (length (state-call :owned-writer-outcomes writer))))
            (is (eq :interrupted
                    (catch 'read-exit
                      (let ((libtmux.internal::*process-launched-hook*
                              (lambda (job)
                                (incf launches)
                                (when (or (and (eq scenario :preflight) (= launches 2))
                                          (and (eq scenario :closing-control)
                                               (some (lambda (argument) (and (search "show-options" argument)
                                                                            (search key argument)))
                                                     (libtmux.internal::process-job-argv job))
                                               (= 2 (incf controls))))
                                  (throw 'read-exit :interrupted)))))
                        (state-call :retire-owned-writer-records writer)))))
            (is (eq :failed (getf (state-call :owned-writer-data writer) :stage)))
            (is (= (+ before (if (eq scenario :preflight) 1 4))
                   (length (state-call :owned-writer-outcomes writer))))))))))
