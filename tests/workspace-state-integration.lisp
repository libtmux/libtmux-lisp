(in-package #:libtmux.tests)

(in-suite workspace-integration)

(defun state-call (name &rest arguments)
  (apply #'uiop:symbol-call :libtmux.workspace name arguments))

(defun state-fixture-declaration (&optional (name "fixture") (id "acquisition"))
  (state-call :make-owned-declaration
              (list :schema "libtmux.lisp.workspace/2" :id id
                    :session (list :id "main" :name name :windows
                                   #((:id "shell" :name "owned-window" :index 0
                                      :panes #((:id "shell" :command #("/bin/cat")))))))))

(defun install-state-bundle (fixture kind record revision)
  (multiple-value-bind (descriptor chunks) (state-call :encode-owned-record record)
    (fixture-ok fixture "set-option" "-s" "--"
                (state-call :owned-record-key "acquisition" kind revision) descriptor)
    (loop for chunk across chunks for index from 0
          do (fixture-ok fixture "set-option" "-s" "--"
                         (state-call :owned-record-key "acquisition" kind revision index) chunk))
    (list :revision revision
          :bytes (length (libtmux.internal::encode-utf8 (state-call :owned-record-json record)))
          :chunks (length chunks))))

(defun install-state-fixture (fixture client)
  ;; Fixture preparation writes complete static records; it does not test a writer.
  (fixture-ok fixture "set-window-option" "-g" "automatic-rename" "off")
  (fixture-ok fixture "rename-window" "-t" "@0" "owned-window")
  (let* ((snapshot (libtmux:fetch-snapshot client))
         (provenance (libtmux:provenance snapshot))
         (declaration (state-fixture-declaration))
         (revision (make-string 32 :initial-element #\A))
         (data (state-call :owned-declaration-data declaration))
         (pending (state-call :make-owned-record :pending
                             (list :schema "libtmux.lisp.workspace.pending/1"
                                   :workspace "acquisition" :base "0" :writer revision :declaration data)))
         (pending-reference (install-state-bundle fixture :pending pending revision))
         (committed
           (state-call :make-owned-record :committed
                       (list :schema "libtmux.lisp.workspace.owned/1" :workspace "acquisition"
                             :revision revision
                             :daemon (list :pid (getf provenance :server/pid)
                                           :start (getf provenance :server/start-time)
                                           :process-start (getf provenance :server/process-start)
                                           :device (getf provenance :server/socket-device)
                                           :inode (getf provenance :server/socket-inode)
                                           :version (getf provenance :server/version))
                             :declaration data :session '(:logical-id "main" :physical-id "$0" :name "fixture")
                             :windows (vector (list :logical-id "shell" :physical-id "@0" :session-id "$0"
                                                    :index 0 :name "owned-window"
                                                    :layout (libtmux:field-value (aref (libtmux:windows snapshot) 0)
                                                                                :window/layout)
                                                    :panes #((:logical-id "shell" :physical-id "%0"))))
                             :previous nil :pending pending-reference))))
    (install-state-bundle fixture :committed committed revision)
    (fixture-ok fixture "set-option" "-s" "--"
                (concatenate 'string (state-call :owned-namespace "acquisition") "control")
                (state-call :make-owned-control :idle revision))
    (values declaration committed pending)))

(defun state-failure (function)
  (handler-case (progn (funcall function) (error "Invalid workspace state was accepted"))
    (libtmux.workspace::owned-state-error (condition) condition)))

(test owned-state-acquisition-is-explicit-and-inspection-is-local
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (calls 0)
             (libtmux.internal::*process-launched-hook*
               (lambda (job) (declare (ignore job)) (incf calls)))
             (state (state-call :fetch-owned-state client declaration)))
        (is (= calls (length (state-call :owned-state-outcomes state))))
        (fixture-ok fixture "rename-window" "-t" "@0" "observed-drift")
        (let* ((later (state-call :fetch-owned-state client declaration))
               (libtmux.internal::*process-launched-hook*
                 (lambda (job) (declare (ignore job)) (error "Local workspace inspection launched I/O")))
               (data (state-call :owned-state-data later)))
          (is (eq :owned (getf data :status)))
          (is (string= "owned-window" (libtmux:name (aref (libtmux:windows (state-call :owned-state-snapshot state)) 0))))
          (is (string= "observed-drift" (libtmux:name (aref (libtmux:windows (state-call :owned-state-snapshot later)) 0))))
          (is (plusp (length (state-call :owned-state-outcomes later))))
          (setf (char (getf (getf data :committed) :workspace) 0) #\X)
          (is (string= "acquisition" (getf (getf (state-call :owned-state-data later) :committed) :workspace))))))))

(test owned-state-vacancy-needs-both-empty-namespace-and-free-name
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((free (state-fixture-declaration "new-session" "free")))
        (is (eq :vacant (getf (state-call :owned-state-data (state-call :fetch-owned-state client free)) :status)))
        (signals libtmux.workspace:workspace-error
          (state-call :fetch-owned-state client (state-fixture-declaration "fixture" "free")))
        (fixture-ok fixture "set-option" "-s" "--" "@libtmux.workspace.66726565.orphan" "value")
        (signals libtmux.workspace:workspace-error (state-call :fetch-owned-state client free))))))

(test owned-state-refusals-retain-read-evidence-and-budget-failures
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (revision (make-string 32 :initial-element #\A))
             (other (make-string 32 :initial-element #\B))
             (control (concatenate 'string (state-call :owned-namespace "acquisition") "control")))
        (fixture-ok fixture "set-option" "-s" "--" control
                    (state-call :make-owned-control :busy revision other))
        (let ((failure (state-failure (lambda () (state-call :fetch-owned-state client declaration)))))
          (is (plusp (length (state-call :owned-state-error-outcomes failure)))))
        (fixture-ok fixture "set-option" "-s" "--" control (state-call :make-owned-control :idle revision))
        (let ((orphan (state-call :owned-record-key "acquisition" :pending other)))
          (fixture-ok fixture "set-option" "-s" "--" orphan "orphan")
          (state-failure (lambda () (state-call :fetch-owned-state client declaration)))
          (fixture-ok fixture "set-option" "-s" "-u" "--" orphan))
        (fixture-ok fixture "set-option" "-s" "-u" "--"
                    (state-call :owned-record-key "acquisition" :committed revision 0))
        (let* ((failure (state-failure (lambda () (state-call :fetch-owned-state client declaration))))
               (outcomes (state-call :owned-state-error-outcomes failure)))
          (is (some (lambda (outcome) (eq :failed (libtmux:outcome-status outcome))) outcomes))
          (is (= 1 (length (libtmux:sessions (libtmux:fetch-snapshot client))))))
        (let ((failure (state-failure
                        (lambda () (state-call :fetch-owned-state client declaration :record-limit 1)))))
          (is (typep (libtmux:error-cause failure) 'libtmux:output-limit-exceeded)))
        (fixture-ok fixture "set-option" "-s" "command-alias[100]" "state-test=display-message")
        (let* ((failure (state-failure
                         (lambda () (state-call :fetch-owned-state client declaration :output-limit 1))))
               (outcomes (state-call :owned-state-error-outcomes failure)))
          (is (= 1 (length outcomes)))
          (is (eq (libtmux:error-outcome (libtmux:error-cause failure)) (aref outcomes 0))))))))

(defun state-control-race (fixture client declaration &optional record-limit)
  (let ((reads 0) (caps nil)
        (control (concatenate 'string (state-call :owned-namespace "acquisition") "control")))
    (let* ((libtmux.internal::*process-launched-hook*
             (lambda (job)
               (push (libtmux.internal::process-job-cap job) caps)
               (when (some (lambda (argument) (search control argument))
                           (libtmux.internal::process-job-argv job))
                 (when (= 2 (incf reads))
                   (fixture-ok fixture "set-option" "-s" "--" control
                               (state-call :make-owned-control :busy
                                           (make-string 32 :initial-element #\A)
                                           (make-string 32 :initial-element #\B)))))))
           (failure (state-failure
                     (lambda ()
                       (apply #'state-call :fetch-owned-state client declaration
                              :output-limit 1048576
                              (when record-limit (list :record-limit record-limit)))))))
      (values failure reads (nreverse caps)))))

(test owned-state-control-restart-keeps-one-byte-and-record-ledger
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (rows (count #\Newline (fixture-ok fixture "show-options" "-s" "-H"))))
        (multiple-value-bind (failure reads caps) (state-control-race fixture client declaration)
          (declare (ignore failure))
          (is (= 3 reads))
          (is (every #'>= caps (rest caps))))
        (fixture-ok fixture "set-option" "-s" "--"
                    (concatenate 'string (state-call :owned-namespace "acquisition") "control")
                    (state-call :make-owned-control :idle (make-string 32 :initial-element #\A)))
        ;; Two inventories/controls, four bundle leaves, one group and one geometry row.
        (multiple-value-bind (failure reads caps)
            (state-control-race fixture client declaration (+ (* 2 rows) 8))
          (declare (ignore caps))
          (is (= 3 reads))
          (is (typep (libtmux:error-cause failure) 'libtmux:output-limit-exceeded)))))))

(test owned-state-replacement-cannot-rebind-the-original-reader
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client)) (replaced nil)
             (libtmux.internal::*process-launched-hook*
               (lambda (job)
                 (when (and (not replaced)
                            (some (lambda (argument) (search "session/1" argument))
                                  (libtmux.internal::process-job-argv job)))
                   (setf replaced t)
                   (fixture-ok fixture "kill-server")
                   (fixture-ok fixture "new-session" "-d" "-s" "replacement" "/bin/cat")))))
        (let ((failure (state-failure (lambda () (state-call :fetch-owned-state client declaration)))))
          (is-true replaced)
          (is (plusp (length (state-call :owned-state-error-outcomes failure)))))))))

(test owned-state-reads-one-previous-bundle-without-chasing-retired-intent
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (multiple-value-bind (declaration old intent) (install-state-fixture fixture client)
        (let* ((head (make-string 32 :initial-element #\A))
               (next (make-string 32 :initial-element #\B))
               (data (state-call :owned-record-data old))
               (pending (state-call :owned-record-data intent))
               (old-size (length (libtmux.internal::encode-utf8 (state-call :owned-record-json old)))))
          (setf (getf pending :base) head (getf pending :writer) next)
          (setf (getf data :revision) next
                (getf data :previous) (list :revision head :bytes old-size :chunks (ceiling old-size 2048))
                (getf data :pending) (install-state-bundle
                                     fixture :pending (state-call :make-owned-record :pending pending) next))
          (install-state-bundle fixture :committed (state-call :make-owned-record :committed data) next)
          (fixture-ok fixture "set-option" "-s" "-u" "--"
                      (state-call :owned-record-key "acquisition" :pending head))
          (fixture-ok fixture "set-option" "-s" "-u" "--"
                      (state-call :owned-record-key "acquisition" :pending head 0))
          (fixture-ok fixture "set-option" "-s" "--"
                      (concatenate 'string (state-call :owned-namespace "acquisition") "control")
                      (state-call :make-owned-control :idle next))
          (let ((observed (state-call :owned-state-data (state-call :fetch-owned-state client declaration))))
            (is (string= head (getf (getf observed :previous) :revision)))
            (is (string= next (getf (getf observed :pending) :writer))))
          (setf (getf pending :base) "0"
                (getf data :pending) (install-state-bundle
                                     fixture :pending (state-call :make-owned-record :pending pending) next))
          (install-state-bundle fixture :committed (state-call :make-owned-record :committed data) next)
          (let ((failure (state-failure (lambda () (state-call :fetch-owned-state client declaration)))))
            (is (typep (libtmux:error-cause failure) 'libtmux.workspace:invalid-workspace))))))))

(test owned-state-late-failure-preserves-structured-local-evidence
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (multiple-value-bind (declaration record) (install-state-fixture fixture client)
        (let ((data (state-call :owned-record-data record)))
          (setf (getf (getf data :daemon) :pid) 99)
          (install-state-bundle fixture :committed
                                (state-call :make-owned-record :committed data)
                                (make-string 32 :initial-element #\A)))
        (let* ((failure (state-failure (lambda () (state-call :fetch-owned-state client declaration))))
               (libtmux.internal::*process-launched-hook*
                 (lambda (job) (declare (ignore job)) (error "Condition inspection launched I/O")))
               (data (state-call :owned-state-error-data failure))
               (snapshot (state-call :owned-state-error-snapshot failure)))
          (is (typep (libtmux:error-cause failure) 'libtmux.workspace:workspace-conflict))
          (is (= 1 (length (libtmux:sessions snapshot))))
          (is (= 99 (getf (getf (getf data :committed) :daemon) :pid)))
          (is (equalp #(("$0")) (getf data :groups)))
          (is (eq t (getf (aref (getf (getf data :geometry) :windows) 0) :regular-p)))
          (is (stringp (getf data :context)))
          (is (integerp (getf data :generation)))
          (is (<= (getf data :acquired-start) (getf data :acquired-end)))
          (setf (char (getf (getf data :committed) :workspace) 0) #\X)
          (is (string= "acquisition"
                       (getf (getf (state-call :owned-state-error-data failure) :committed) :workspace))))))))

(test owned-state-closing-failure-does-not-replace-the-primary-metadata-error
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((declaration (install-state-fixture fixture client)))
        (fixture-ok fixture "set-option" "-s" "--"
                    (state-call :owned-record-key "acquisition" :committed
                                (make-string 32 :initial-element #\A)) "broken")
        (let* ((rows (count #\Newline (fixture-ok fixture "show-options" "-s" "-H")))
               (failure (state-failure
                         (lambda () (state-call :fetch-owned-state client declaration
                                                :record-limit (+ rows 2)))))
               (causes (state-call :owned-state-error-causes failure)))
          (is (typep (libtmux:error-cause failure) 'libtmux.workspace:invalid-workspace))
          (is (= 2 (length causes)))
          (is (typep (aref causes 1) 'libtmux:output-limit-exceeded)))))))

(test owned-state-intent-comparison-is-case-sensitive
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (multiple-value-bind (declaration committed pending) (install-state-fixture fixture client)
        (let* ((intent (state-call :owned-record-data pending))
               (data (state-call :owned-record-data committed))
               (session (getf (getf intent :declaration) :session))
               (pane (aref (getf (aref (getf session :windows) 0) :panes) 0))
               (revision (make-string 32 :initial-element #\A)))
          (setf (aref (getf pane :command) 0) "/BIN/CAT"
                (getf data :pending) (install-state-bundle
                                     fixture :pending (state-call :make-owned-record :pending intent) revision))
          (install-state-bundle fixture :committed (state-call :make-owned-record :committed data) revision)
          (let ((failure (state-failure (lambda () (state-call :fetch-owned-state client declaration)))))
            (is (typep (libtmux:error-cause failure) 'libtmux.workspace:invalid-workspace))))))))
