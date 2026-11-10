(in-package #:libtmux.tests)

(in-suite workspace-publication-integration)

(test owned-apply-candidate-readback-failure-retains-selected-and-observed-metadata
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (state-fixture-declaration "publication-owned" "publication"))
             (before (state-call :apply-owned-workspace client declaration))
             (selected (getf (state-call :owned-result-data before) :record))
             (head (getf selected :revision))
             (wanted (state-call :owned-declaration-data declaration))
             (prepare (symbol-function 'libtmux.workspace::prepare-owned-writer))
             (writer nil) (changed nil) (failure nil))
        (setf (getf (getf wanted :session) :name) "publication-renamed")
        (unwind-protect
             (progn
               (setf (symbol-function 'libtmux.workspace::prepare-owned-writer)
                     (lambda (&rest arguments) (setf writer (apply prepare arguments))))
               (let ((libtmux.internal::*process-launched-hook*
                       (lambda (job)
                         (when (and writer (not changed)
                                    (some (lambda (argument)
                                            (and (search "show-options" argument)
                                                 (search (state-call :owned-record-key "publication" :committed
                                                                     (getf (state-call :owned-writer-data writer) :writer))
                                                         argument)))
                                          (libtmux.internal::process-job-argv job)))
                           (setf changed t)
                           (fixture-ok fixture "set-option" "-s" "--"
                                       (state-call :owned-record-key "publication" :committed
                                                   (getf (state-call :owned-writer-data writer) :writer) 0) "GG")))))
                 (setf failure
                       (apply-failure (lambda () (state-call :apply-owned-workspace client
                                                            (state-call :make-owned-declaration wanted) :reconcile t))))))
          (setf (symbol-function 'libtmux.workspace::prepare-owned-writer) prepare))
        (let* ((data (state-call :owned-apply-error-data failure))
               (token (getf (state-call :owned-writer-data writer) :writer))
               (control (state-call :make-owned-control :busy head token)))
          (is-true changed)
          (is (eq :candidate (getf data :phase)))
          (is (null (getf data :publication-status)))
          (is (state-call :owned-value= selected (getf (getf data :selected-state) :committed)))
          (is (equal head (getf (getf data :record) :revision)))
          (is (equal token (getf (getf data :candidate) :revision)))
          (is (equal control (getf (getf data :observed-state) :control)))
          (is (string= (format nil "~A~%" control)
                       (fixture-ok fixture "show-options" "-s" "-v"
                                   (getf (state-call :owned-writer-data writer) :control-key))))
          (is (plusp (length (state-call :owned-apply-error-outcomes failure))))
          (let ((libtmux.internal::*process-launched-hook*
                  (lambda (job) (declare (ignore job)) (error "Error inspection contacted tmux"))))
            (setf (char (getf (getf (getf data :selected-state) :committed) :revision) 0) #\X)
            (is (equal head (getf (getf (getf (state-call :owned-apply-error-data failure) :selected-state) :committed)
                                      :revision)))))))))

(test owned-apply-preserves-publication-status-when-post-observation-fails
  (dolist (scenario '(:head-changed :server-gone :unknown))
    (with-tmux-fixture (fixture)
      (with-fixture-client (client fixture)
        (let* ((declaration (state-fixture-declaration "publication-owned" "publication"))
               (before (state-call :apply-owned-workspace client declaration))
               (head (getf (getf (state-call :owned-result-data before) :record) :revision))
               (wanted (state-call :owned-declaration-data declaration))
               (publish (symbol-function 'libtmux.workspace::publish-owned-writer))
               (published nil) (writer nil) (calls 0) (late-mutations 0) (failure nil))
          (setf (getf (getf wanted :session) :name) "publication-renamed")
          (unwind-protect
               (progn
                 (setf (symbol-function 'libtmux.workspace::publish-owned-writer)
                       (lambda (resource)
                         (incf calls)
                         (setf writer resource published (funcall publish resource))
                         (ecase scenario
                           (:head-changed
                            (let* ((token (getf (state-call :owned-writer-data resource) :writer))
                                   (next (writer-token (if (string= token (writer-token #\F)) #\E #\F))))
                              (fixture-ok fixture "set-option" "-s" "--"
                                          (getf (state-call :owned-writer-data resource) :control-key)
                                          (state-call :make-owned-control :busy token next))))
                           (:server-gone (fixture-ok fixture "kill-server"))
                           (:unknown
                            (setf (slot-value published 'libtmux::status) :unknown
                                  (slot-value published 'libtmux::reason) :injected-uncertainty)
                            (error 'libtmux:outcome-unknown :outcome published :message "Injected uncertain publication")))
                         published))
                 (let ((libtmux.internal::*process-launched-hook*
                         (lambda (job)
                           (when (and published (workspace-mutation-job-p job)) (incf late-mutations)))))
                   (setf failure
                         (apply-failure (lambda () (state-call :apply-owned-workspace client
                                                              (state-call :make-owned-declaration wanted) :reconcile t))))))
            (setf (symbol-function 'libtmux.workspace::publish-owned-writer) publish))
          (let* ((data (state-call :owned-apply-error-data failure))
                 (token (getf (state-call :owned-writer-data writer) :writer)))
            (is (= 1 calls))
            (is (= 0 late-mutations))
            (is (= 1 (count published (state-call :owned-apply-error-outcomes failure))))
            (is (equal head (getf (getf (getf data :selected-state) :committed) :revision)))
            (is (equal token (getf (getf data :candidate) :revision)))
            (is (eq (if (eq scenario :unknown) :unknown :succeeded) (getf data :publication-status)))
            (is (eq (if (eq scenario :unknown) :publish :observe) (getf data :phase)))
            (is (equal (if (eq scenario :unknown) head token) (getf (getf data :record) :revision)))
            (when (eq scenario :unknown)
              (let ((mutations 0))
                (let* ((libtmux.internal::*process-launched-hook*
                         (lambda (job) (when (workspace-mutation-job-p job) (incf mutations))))
                       (again (state-call :apply-owned-workspace client (state-call :make-owned-declaration wanted))))
                  (is (eq :unchanged (getf (state-call :owned-result-data again) :status)))
                  (is (= 0 mutations)))))))))))
