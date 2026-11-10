(in-package #:libtmux.tests)

(in-suite workspace-apply-race-integration)

(test owned-apply-refuses-invalid-authority-and-unsupported-edits-before-claim
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (namespace (state-call :owned-namespace "acquisition"))
             (control-key (concatenate 'string namespace "control"))
             (control (string-right-trim '(#\Newline) (fixture-ok fixture "show-options" "-s" "-v" control-key))))
        (dolist (scenario '(:unowned :creation-input :removed-pane :busy :tampered))
          (let* ((wanted (state-call :owned-declaration-data declaration))
                 (window (aref (getf (getf wanted :session) :windows) 0))
                 (pane (aref (getf window :panes) 0))
                 (mutations 0))
            (ecase scenario
              (:unowned (setf (getf wanted :id) "unowned"))
              (:creation-input (setf (getf pane :command) #("/bin/echo" "changed")))
              (:removed-pane (setf (getf pane :id) "replacement"))
              (:busy (fixture-ok fixture "set-option" "-s" "--" control-key
                                 (state-call :make-owned-control :busy (writer-token #\A) (writer-token #\B))))
              (:tampered (fixture-ok fixture "set-option" "-s" "--"
                                     (state-call :owned-record-key "acquisition" :committed (writer-token #\A) 0) "GG")))
            (let ((libtmux.internal::*process-launched-hook*
                    (lambda (job) (when (workspace-mutation-job-p job) (incf mutations)))))
              (let* ((failure (apply-failure (lambda () (state-call :apply-owned-workspace client
                                                                   (state-call :make-owned-declaration wanted) :reconcile t))))
                     (data (state-call :owned-apply-error-data failure)))
                (is (member (getf data :phase) '(:acquire :plan)))
                (is (null (getf data :writer)))
                (is (= 0 mutations))))
            (when (eq scenario :busy) (fixture-ok fixture "set-option" "-s" "--" control-key control))))))))

(defun run-owned-step-race (scenario)
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (wanted (state-call :owned-declaration-data declaration))
             (window (aref (getf (getf wanted :session) :windows) 0))
             (execute (symbol-function 'libtmux.workspace::execute-owned-step))
             (changed nil) (failure nil))
        (setf (getf window :panes) (concatenate 'vector (getf window :panes)
                                               #((:id "additional" :command #("/bin/cat")))))
        (unwind-protect
             (progn
               (setf (symbol-function 'libtmux.workspace::execute-owned-step)
                     (lambda (application step)
                       (let ((libtmux.internal::*dispatch-context-check*
                               (lambda (actual witness current)
                                 (declare (ignore actual witness current))
                                 (unless changed
                                   (setf changed t)
                                   (ecase scenario
                                     (:group (fixture-ok fixture "new-session" "-d" "-t" "$0" "-s" "grouped"))
                                     (:same-session-link (fixture-ok fixture "link-window" "-s" "@0" "-t" "$0:9"))
                                     (:foreign-link
                                      (fixture-ok fixture "new-session" "-d" "-s" "other" "--" "/bin/cat")
                                      (fixture-ok fixture "link-window" "-s" "@0" "-t" "other:9"))
                                     (:token
                                      (let ((writer (libtmux.workspace::owned-application-writer application)))
                                        (fixture-ok fixture "set-option" "-s" "--"
                                                    (getf (state-call :owned-writer-data writer) :control-key)
                                                    (state-call :make-owned-control :busy (writer-token #\A) (writer-token #\C)))))
                                     (:floating (fixture-ok fixture "new-pane" "-d" "-t" "%0" "--" "/bin/cat"))
                                     (:modal (fixture-ok fixture "new-pane" "-O" "-d" "-t" "%0" "--" "/bin/cat")))))))
                         (declare (special libtmux.internal::*dispatch-context-check*))
                         (funcall execute application step))))
               (setf failure (apply-failure (lambda () (state-call :apply-owned-workspace client
                                                                  (state-call :make-owned-declaration wanted) :reconcile t)))))
          (setf (symbol-function 'libtmux.workspace::execute-owned-step) execute))
        (let ((data (state-call :owned-apply-error-data failure)))
          (is-true changed)
          (is (eq :execute (getf data :phase)))
          (is (eq :failed (getf (getf data :writer) :stage)))
          (is (null (getf data :publication-status)))
          (is (string= (format nil "~A~%"
                              (if (eq scenario :token)
                                  (state-call :make-owned-control :busy (writer-token #\A) (writer-token #\C))
                                  (getf (getf data :writer) :control)))
                       (fixture-ok fixture "show-options" "-s" "-v" (getf (getf data :writer) :control-key))))
          (is (= (if (member scenario '(:floating :modal)) 2 1)
                 (length (uiop:split-string (string-right-trim '(#\Newline)
                                                              (fixture-ok fixture "list-panes" "-t" "@0" "-F" "#{pane_id}"))
                                           :separator '(#\Newline))))))))))

(test owned-apply-rechecks-sharing-grouping-and-writer-token-at-domain-dispatch
  (dolist (scenario '(:group :same-session-link :foreign-link :token))
    (run-owned-step-race scenario)))

(test owned-apply-rechecks-new-pane-geometry-at-domain-dispatch
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (if (eq :legacy (state-call :owned-geometry-profile (libtmux:tmux-version client)))
          (skip "Floating/modal races require tmux 3.7/3.8")
          (progn
            (run-owned-step-race :floating)
            (when (eq :modal (state-call :owned-geometry-profile (libtmux:tmux-version client)))
              (run-owned-step-race :modal)))))))
