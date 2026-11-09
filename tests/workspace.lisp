(in-package #:libtmux.tests)

(in-suite workspace)

(defclass explosive-workspace-key () ())

(defmethod print-object ((object explosive-workspace-key) stream)
  (declare (ignore object stream))
  (error "Workspace validation invoked an untrusted printer"))

(defun example-workspace-data ()
  (list :schema (copy-seq "libtmux.lisp.workspace/1")
        :session
        (list :name (copy-seq "workspace")
              :cwd (copy-seq "/srv/app")
              :windows
              (vector
               (list :name (copy-seq "editor")
                     :index 1
                     :layout :tiled
                     :panes
                     (vector (list :command (vector (copy-seq "/bin/cat")))
                             (list :cwd (copy-seq "/srv/app/sub")
                                   :command (vector (copy-seq "/bin/cat")))))
               (list :name (copy-seq "shell")
                     :index 4
                     :panes (vector (list :command (vector (copy-seq "/bin/cat")))))))))

(defun workspace-call (name &rest arguments)
  (apply #'uiop:symbol-call :libtmux.workspace name arguments))

(defun workspace-condition-p (condition name)
  (let ((symbol (find-symbol (string name) :libtmux.workspace)))
    (and symbol (typep condition symbol))))

(defun workspace-creation-inputs ()
  (let ((data (example-workspace-data)))
    (setf (getf (getf data :session) :environment)
          (vector (cons (copy-seq "APP_VALUE") (copy-seq "λ$; value"))
                  (cons (copy-seq "EMPTY") (copy-seq ""))))
    (let ((window (aref (getf (getf data :session) :windows) 0)))
      (setf (getf window :layout) (list :custom (copy-seq "layout text"))
            (aref (getf window :panes) 0)
            (list :shell-command (copy-seq "exec cat \"$APP_VALUE\""))))
    data))

(test workspace-explicit-creation-inputs-own-data-and-plan-operands
  (let* ((source (workspace-creation-inputs))
         (workspace (workspace-call :make-workspace source))
         (expected (workspace-call :workspace-data workspace))
         (plan (workspace-call :plan-workspace workspace)))
    (setf (char (cdr (aref (getf (getf source :session) :environment) 0)) 0) #\X)
    (let ((window (aref (getf (getf source :session) :windows) 0)))
      (setf (char (second (getf window :layout)) 0) #\X
            (char (getf (aref (getf window :panes) 0) :shell-command) 0) #\X))
    (let* ((data (workspace-call :workspace-data workspace))
           (session (getf data :session))
           (window (aref (getf session :windows) 0)))
      (is (equalp expected data))
      (is (typep (getf session :environment) 'simple-vector))
      (setf (char (cdr (aref (getf session :environment) 0)) 0) #\X
            (char (second (getf window :layout)) 0) #\X
            (char (getf (aref (getf window :panes) 0) :shell-command) 0) #\X)
      (is (equalp expected (workspace-call :workspace-data workspace))))
    (let* ((steps (workspace-call :plan-steps plan))
           (first (workspace-call :step-data (aref steps 0)))
           (layout (workspace-call :step-data
                                   (find :select-layout steps
                                         :key (lambda (step)
                                                (workspace-call :step-action step))))))
      (is (string= "exec cat \"$APP_VALUE\"" (getf first :shell-command)))
      (is (equalp #(("APP_VALUE" . "λ$; value") ("EMPTY" . ""))
                  (getf first :environment)))
      (is (equal '(:custom "layout text") (getf layout :layout)))
      (setf (char (getf first :shell-command) 0) #\X)
      (is (string= "exec cat \"$APP_VALUE\""
                   (getf (workspace-call :step-data (aref steps 0)) :shell-command))))))

(defmacro signals-workspace (name &body body)
  `(handler-case
       (progn ,@body (fail "Expected ~A" ,name))
     (condition (condition)
       (if (workspace-condition-p condition ,name)
           (is-true t)
           (error condition)))))

(test workspace-native-data-is-owned-and-plans-deterministically
  (let* ((source (example-workspace-data))
         (workspace (workspace-call :make-workspace source))
         (data (workspace-call :workspace-data workspace))
         (plan (workspace-call :plan-workspace workspace))
         (steps (workspace-call :plan-steps plan)))
    (setf (char (getf (getf source :session) :name) 0) #\X
          (char (getf (getf data :session) :name) 0) #\Y
          (aref steps 0) nil)
    (is (string= "workspace"
                 (getf (getf (workspace-call :workspace-data workspace) :session)
                       :name)))
    (let ((actions
            (map 'list
                 (lambda (step) (workspace-call :step-action step))
                 (workspace-call :plan-steps plan))))
      (is (equal '(:create-session :move-window :split-pane :select-layout
                   :create-window)
                 actions)))
    (let* ((first (aref (workspace-call :plan-steps plan) 0))
           (step-data (workspace-call :step-data first)))
      (setf (char (getf step-data :session-name) 0) #\Z)
      (is (string= "workspace"
                   (getf (workspace-call :step-data first) :session-name))))))

(test workspace-native-data-rejects-open-or-unsafe-shapes
  (dolist
      (data
       (list
        nil
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #()) :extra t)
        '(:schema "libtmux.lisp.workspace/1"
          :schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #()))
        '(:schema "foreign" :session (:name "x" :windows #()))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "" :windows #()))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "same" :panes #())
                                            (:name "same" :panes #()))))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "w" :index -1
                                           :panes #(())))))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "w" :layout :unknown
                                           :panes #(())))))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "w"
                                           :panes #((:command #()))))))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "w"
                                           :panes #((:command #("-bad")))))))))
    (signals-workspace :invalid-workspace
      (workspace-call :make-workspace data))))

(test workspace-native-data-rejects-unpreserved-names-and-opaque-keys
  (dolist (name '("floor:colon" "floor.period"))
    (signals-workspace :invalid-workspace
      (workspace-call
       :make-workspace
       `(:schema "libtmux.lisp.workspace/1"
         :session (:name ,name :windows #((:name "main" :panes #(()))))))))
  (signals-workspace :invalid-workspace
    (workspace-call
     :make-workspace
     (list :schema "libtmux.lisp.workspace/1"
           :session (list :name "safe" :windows
                          (vector (list :name (format nil "bad~%name")
                                        :panes #(())))))))
  (signals-workspace :invalid-workspace
    (workspace-call
     :make-workspace
     (list (make-instance 'explosive-workspace-key) t))))

(test workspace-plan-reserves-explicit-indexes-before-unspecified-windows
  (let* ((workspace
           (workspace-call
            :make-workspace
            '(:schema "libtmux.lisp.workspace/1"
              :session (:name "reserved"
                        :windows #((:name "floating" :panes #(()))
                                   (:name "zero" :index 0 :panes #(()))
                                   (:name "automatic" :panes #(())))))))
         (steps (workspace-call :plan-steps
                                (workspace-call :plan-workspace workspace))))
    (is (equal '(:create-session :move-window :create-window :create-window)
               (map 'list (lambda (step) (workspace-call :step-action step)) steps)))
    (is (= 1 (getf (workspace-call :step-data (aref steps 1)) :index)))
    (is (string= "zero"
                 (getf (workspace-call :step-data (aref steps 2)) :window-name)))
    (is (string= "automatic"
                 (getf (workspace-call :step-data (aref steps 3)) :window-name)))))

(test workspace-native-data-rejects-cycles-and-limit-exhaustion
  (let ((cycle (list :schema "libtmux.lisp.workspace/1")))
    (setf (cddr cycle) cycle)
    (signals-workspace :invalid-workspace
      (workspace-call :make-workspace cycle)))
  (signals-workspace :invalid-workspace
    (workspace-call :make-workspace (example-workspace-data) :max-windows 1))
  (signals-workspace :invalid-workspace
    (workspace-call :make-workspace (example-workspace-data) :max-panes 1))
  (signals-workspace :invalid-workspace
    (workspace-call :make-workspace (example-workspace-data) :max-argv 0)))

(defun workspace-snapshot (&key (name "workspace")
                                (windows '(("editor" 1 2) ("shell" 4 1))))
  (let ((session-id "$21")
        (link-rows nil)
        (pane-rows nil))
    (loop for (window-name index pane-count) in windows
          for window-number from 31
          for window-id = (format nil "@~D" window-number)
          do (push (list "window-link/1" session-id (write-to-string index)
                         window-id window-name "120" "30"
                         (write-to-string pane-count)
                         (if (= index (second (first windows))) "1" "0") "")
                   link-rows)
             (dotimes (pane-index pane-count)
               (push (list "pane/1" session-id (write-to-string index) window-id
                           (format nil "%25~D" (+ (* window-number 10) pane-index))
                           (write-to-string pane-index)
                           (if (zerop pane-index) "1" "0") "120" "30" "cat"
                           "/srv/app" "" "100" "0" "cat")
                     pane-rows)))
    (libtmux.internal::build-snapshot
     (gensym "WORKSPACE-SERVER-") 1
     '(:server/socket-path "workspace.sock" :server/version "3.8")
     (synthetic-rows
      :session
      (list (list "session/1" session-id name "1" "0"
                  (write-to-string (length windows)))))
     (synthetic-rows :window-link (nreverse link-rows))
     (synthetic-rows :pane (nreverse pane-rows))
     #())))

(test workspace-planning-reuses-only-an-exact-captured-topology
  (let* ((workspace (workspace-call :make-workspace (example-workspace-data)))
         (snapshot (workspace-snapshot))
         (calls 0)
         (libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (incf calls))))
    (is (zerop (length (workspace-call :plan-steps
                                       (workspace-call :plan-workspace workspace snapshot)))))
    (is (zerop calls))
    (dolist (conflict
             (list (workspace-snapshot :name "other")
                   (workspace-snapshot :windows '(("editor" 1 1) ("shell" 4 1)))
                   (workspace-snapshot :windows '(("editor" 2 2) ("shell" 4 1)))
                   (workspace-snapshot :windows '(("editor" 1 2)))
                   (workspace-snapshot :windows '(("editor" 1 2) ("shell" 4 1)
                                                  ("extra" 5 1)))))
      (if (string= "other" (libtmux:name (aref (libtmux:sessions conflict) 0)))
          (is (plusp (length (workspace-call :plan-steps
                                             (workspace-call :plan-workspace workspace conflict)))))
          (signals-workspace :workspace-conflict
            (workspace-call :plan-workspace workspace conflict))))
    (is (zerop calls))))

(defparameter +workspace-json+
  "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"workspace\",\"cwd\":\"/srv/app\",\"windows\":[{\"name\":\"editor\",\"index\":1,\"layout\":\"tiled\",\"panes\":[{\"command\":[\"/bin/cat\"]},{\"cwd\":\"/srv/app/sub\",\"command\":[\"/bin/cat\"]}]},{\"name\":\"shell\",\"index\":4,\"panes\":[{\"command\":[\"/bin/cat\"]}]}]}}")

(test workspace-json-matches-native-owned-data
  (let* ((native (workspace-call :make-workspace (example-workspace-data)))
         (parsed (workspace-call :parse-workspace +workspace-json+))
         (data (workspace-call :workspace-data parsed)))
    (is (equalp (workspace-call :workspace-data native) data))
    (setf (char (getf (getf data :session) :name) 0) #\X)
    (is (string= "workspace"
                 (getf (getf (workspace-call :workspace-data parsed) :session)
                       :name)))))

(test workspace-json-is-closed-complete-and-does-not-intern-names
  (let ((unknown "LIBTMUX-UNTRUSTED-WORKSPACE-MEMBER-91F4"))
    (is (null (find-symbol unknown :keyword)))
    (dolist
        (document
         (list
          "{}"
          "null"
          "{\"schema\":\"foreign\",\"session\":{\"name\":\"x\",\"windows\":[]}}"
          "{\"schema\":\"libtmux.lisp.workspace/1\",\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"x\",\"windows\":[]}}"
          "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"x\",\"windows\":[]},\"extra\":true}"
          "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":null}"
          "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"x\",\"windows\":[{\"name\":\"w\",\"index\":1.5,\"panes\":[{}]}]}}"
          (concatenate 'string +workspace-json+ " true")
          (format nil
                  "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"x\",\"windows\":[],\"~A\":true}}"
                  unknown)))
      (signals-workspace :invalid-workspace-document
        (workspace-call :parse-workspace document)))
    (is (null (find-symbol unknown :keyword)))))

(test workspace-json-enforces-every-structural-bound
  (dolist (case
           `(((:max-input-bytes 20) :max-input-bytes)
             ((:max-depth 2) :max-depth)
             ((:max-nodes 4) :max-nodes)
             ((:max-string-length 8) :max-string-length)
             ((:max-windows 1) :max-windows)
             ((:max-panes 2) :max-panes)
             ((:max-argv 0) :max-argv)
             ((:max-integer-digits 0) :max-integer-digits)))
    (destructuring-bind (arguments expected-limit) case
      (handler-case
          (progn
            (apply #'workspace-call :parse-workspace +workspace-json+ arguments)
            (fail "Expected workspace limit ~S" expected-limit))
        (condition (condition)
          (unless (workspace-condition-p condition :workspace-limit-exceeded)
            (error condition))
          (is (eq expected-limit (workspace-call :workspace-limit condition)))))))
  (handler-case
      (progn
        (workspace-call :parse-workspace
                        "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"x\",\"windows\":[],\"extra\":true}}")
        (fail "Expected a path-bearing workspace document error"))
    (condition (condition)
      (unless (workspace-condition-p condition :invalid-workspace-document)
        (error condition))
      (let ((path (workspace-call :workspace-path condition)))
        (is (string= "extra" (aref path (1- (length path)))))
        (setf (char (aref path (1- (length path))) 0) #\X)
        (is (string= "extra"
                     (aref (workspace-call :workspace-path condition)
                           (1- (length path)))))))))

(test workspace-file-loading-is-bounded-and-requires-a-regular-file
  (let* ((directory (uiop:ensure-directory-pathname
                     (sb-posix:mkdtemp "/tmp/libtmux-workspace-XXXXXX")))
         (path (merge-pathnames "workspace.json" directory))
         (fifo (merge-pathnames "workspace.fifo" directory)))
    (unwind-protect
         (progn
           (with-open-file (stream path :direction :output :if-exists :error
                                        :external-format :utf-8)
             (write-string +workspace-json+ stream))
           (is (typep (workspace-call :read-workspace path)
                      (find-symbol "WORKSPACE" :libtmux.workspace)))
           (handler-case
               (progn
                 (workspace-call :read-workspace path :max-input-bytes 20)
                 (fail "Oversized workspace file was accepted"))
             (condition (condition)
               (unless (workspace-condition-p condition :workspace-limit-exceeded)
                 (error condition))
               (is (eq :max-input-bytes
                       (workspace-call :workspace-limit condition)))))
           (signals-workspace :invalid-workspace-document
             (workspace-call :read-workspace #P"/dev/null"))
           (sb-posix:mkfifo (namestring fifo) #o600)
           (signals-workspace :invalid-workspace-document
             (workspace-call :read-workspace fifo)))
      (uiop:delete-directory-tree directory :validate t))))

(defun fake-workspace-outcome (&key value (present-p t))
  (make-instance 'libtmux:command-outcome
                 :status :succeeded :phase :exited :arguments #("workspace-test")
                 :stdout #() :stderr #() :exit-code 0 :elapsed 0.0
                 :value value :present-p present-p))

(test workspace-apply-retains-the-failing-step-and-partial-outcomes
  (let* ((workspace (workspace-call :make-workspace (example-workspace-data)))
         (snapshot (workspace-snapshot :name "other"))
         (client (make-instance 'libtmux:client))
         (calls 0)
         (libtmux.workspace::*fetch-snapshot-function*
           (lambda (ignored-client &rest options)
             (declare (ignore ignored-client options))
             snapshot))
         (libtmux.workspace::*execute-step-function*
           (lambda (step ignored-client state options)
             (declare (ignore ignored-client options))
             (incf calls)
             (if (= calls 2)
                 (let ((outcome (make-instance 'libtmux:command-outcome
                                               :status :failed :phase :exited
                                               :arguments #("failed")
                                               :stdout #() :stderr #()
                                               :exit-code 1 :elapsed 0.0)))
                   (error 'libtmux:command-failed :message "injected"
                          :outcome outcome))
                 (values (fake-workspace-outcome) (or state step))))))
    (unwind-protect
         (handler-case
             (progn
               (workspace-call :apply-workspace client workspace)
               (fail "Partial workspace application succeeded"))
           (condition (condition)
             (unless (workspace-condition-p condition :workspace-apply-failed)
               (error condition))
             (is (= 2 (length (workspace-call :result-outcomes condition))))
             (is (eq :move-window
                     (workspace-call
                      :step-action (workspace-call :failed-step condition))))
             (is (typep (libtmux:error-cause condition)
                        'libtmux:command-failed))))
      (libtmux:close-client client))))

(test workspace-apply-retains-outcome-when-post-command-state-validation-fails
  (let* ((workspace (workspace-call :make-workspace (example-workspace-data)))
         (initial (workspace-snapshot :name "other"))
         (created (workspace-snapshot))
         (foreign (workspace-snapshot :name "foreign"
                                      :windows '(("foreign" 8 1))))
         (client (make-instance 'libtmux:client))
         (calls 0)
         (second-outcome nil)
         (libtmux.workspace::*fetch-snapshot-function*
           (lambda (ignored-client &rest options)
             (declare (ignore ignored-client options))
             initial))
         (libtmux.workspace::*execute-step-function*
           (lambda (step ignored-client state options)
             (declare (ignore step ignored-client options))
             (incf calls)
             (if (= calls 1)
                 (let* ((session (aref (libtmux:sessions created) 0))
                        (window (libtmux:window (aref (libtmux:window-links session) 0))))
                   (values (fake-workspace-outcome)
                           (libtmux.workspace::make-apply-state
                            :session session :window window)))
                 (let ((window (aref (libtmux:windows foreign) 0)))
                   (setf second-outcome (fake-workspace-outcome :value window))
                   (libtmux.workspace::state-with-window state window second-outcome))))))
    (unwind-protect
         (handler-case
             (progn
               (workspace-call :apply-workspace client workspace)
               (fail "Post-command state validation succeeded"))
           (condition (condition)
             (unless (workspace-condition-p condition :workspace-apply-failed)
               (error condition))
             (let ((outcomes (workspace-call :result-outcomes condition)))
               (is (= 2 (length outcomes)))
               (is (eq second-outcome (aref outcomes 1))))
             (is (eq second-outcome
                     (libtmux:error-outcome (libtmux:error-cause condition))))))
      (libtmux:close-client client))))

(test workspace-apply-retains-successful-mutations-when-final-proof-fails
  (let* ((workspace (workspace-call :make-workspace (example-workspace-data)))
         (snapshot (workspace-snapshot :name "other"))
         (client (make-instance 'libtmux:client))
         (fetches 0)
         (executions 0)
         (libtmux.workspace::*fetch-snapshot-function*
           (lambda (ignored-client &rest options)
             (declare (ignore ignored-client options))
             (if (= 1 (incf fetches))
                 snapshot
                 (error 'libtmux:incomplete-snapshot
                        :message "injected final proof failure"))))
         (libtmux.workspace::*execute-step-function*
           (lambda (step ignored-client state options)
             (declare (ignore step ignored-client options))
             (incf executions)
             (values (fake-workspace-outcome) state))))
    (unwind-protect
         (handler-case
             (progn
               (workspace-call :apply-workspace client workspace)
               (fail "Unproved workspace application succeeded"))
           (condition (condition)
             (unless (workspace-condition-p condition :workspace-apply-failed)
               (error condition))
             (is (null (workspace-call :failed-step condition)))
             (is (= executions
                    (length (workspace-call :result-outcomes condition))))
             (is (= 5 executions))
             (is (typep (libtmux:error-cause condition)
                        'libtmux:incomplete-snapshot))))
      (libtmux:close-client client))))

(defmacro with-workspace-clock ((now) &body body)
  (let ((original (gensym "CLOCK")))
    `(let ((,now 0)
           (,original (symbol-function 'libtmux.internal::monotonic-seconds)))
       (unwind-protect
            (progn
              (setf (symbol-function 'libtmux.internal::monotonic-seconds)
                    (lambda () ,now))
              ,@body)
         (setf (symbol-function 'libtmux.internal::monotonic-seconds) ,original)))))

(test workspace-total-budget-caps-each-core-call-without-resetting
  (dolist (explicit-timeout-p '(nil t))
    (let ((client (make-instance 'libtmux:client :timeout 2)))
      (unwind-protect
           (with-workspace-clock (now)
             (let* ((workspace (workspace-call :make-workspace (example-workspace-data)))
                    (initial (workspace-snapshot :name "other"))
                    (final (workspace-snapshot))
                    (token (libtmux:make-cancellation-token))
                    (fetches 0) (calls nil)
                    (libtmux.workspace::*fetch-snapshot-function*
                      (lambda (ignored-client &rest options)
                        (declare (ignore ignored-client))
                        (push (copy-list options) calls)
                        (incf now)
                        (if (= 1 (incf fetches)) initial final)))
                    (libtmux.workspace::*execute-step-function*
                      (lambda (step ignored-client state options)
                        (declare (ignore step ignored-client))
                        (push (copy-list options) calls)
                        (incf now)
                        (values (fake-workspace-outcome) state))))
               (let ((result
                       (apply #'workspace-call :apply-workspace client workspace
                              :total-timeout 8 :cancel-token token :output-limit 8192
                              (when explicit-timeout-p (list :timeout 4)))))
                 (is (eq final (workspace-call :result-snapshot result)))
                 (is (= 5 (length (workspace-call :result-outcomes result))))
                 (is (every (lambda (options) (eq token (getf options :cancel-token))) calls))
                 (is (every (lambda (options) (= 8192 (getf options :output-limit))) calls))
                 (is (equal (if explicit-timeout-p '(4 4 4 4 4 3 2)
                                '(2 2 2 2 2 2 2))
                            (mapcar (lambda (options) (getf options :timeout))
                                    (nreverse calls)))))))
        (libtmux:close-client client)))))

(test workspace-total-budget-refuses-later-work-and-retains-completed-outcomes
  (dolist (phase '(:before-fetch :reuse :before-first-step :between-steps :final-proof))
    (let ((client (make-instance 'libtmux:client)))
      (unwind-protect
           (with-workspace-clock (now)
             (let* ((workspace (workspace-call :make-workspace (example-workspace-data)))
                    (initial (workspace-snapshot :name "other"))
                    (final (workspace-snapshot))
                    (fetches 0) (executions 0)
                    (libtmux.workspace::*fetch-snapshot-function*
                      (lambda (ignored-client &rest options)
                        (declare (ignore ignored-client options))
                        (incf fetches)
                        (incf now (if (and (eq phase :final-proof) (= fetches 2)) 2 1))
                        (when (eq phase :before-first-step)
                          (setf (symbol-function 'libtmux.internal::monotonic-seconds)
                                (lambda () (incf now))))
                        (if (or (eq phase :reuse) (= fetches 2)) final initial)))
                    (libtmux.workspace::*execute-step-function*
                      (lambda (step ignored-client state options)
                        (declare (ignore step ignored-client options))
                        (incf executions)
                        (incf now)
                        (values (fake-workspace-outcome) state))))
               (handler-case
                   (progn
                     (workspace-call :apply-workspace client workspace
                                     :total-timeout
                                     (ecase phase
                                       (:before-fetch 0) (:reuse 1)
                                       ((:before-first-step :between-steps) 3)
                                       (:final-proof 8)))
                     (fail "Expired workspace application returned success"))
                 (error (condition)
                   (let* ((partial-p (member phase '(:between-steps :final-proof)))
                          (cause (if partial-p (libtmux:error-cause condition) condition)))
                     (when partial-p
                       (is (workspace-condition-p condition :workspace-apply-failed))
                       (let ((outcomes (workspace-call :result-outcomes condition)))
                         (is (= (if (eq phase :between-steps) 2 5) (length outcomes)))
                         (is (every (lambda (outcome)
                                      (eq :succeeded (libtmux:outcome-status outcome)))
                                    outcomes)))
                       (let ((step (workspace-call :failed-step condition)))
                         (if (eq phase :between-steps)
                             (is (eq :split-pane (workspace-call :step-action step)))
                             (is (null step)))))
                     (is (workspace-condition-p cause :workspace-deadline-exceeded))
                     (is (eq :total-timeout (workspace-call :workspace-limit cause)))
                     (is (eq client (libtmux:error-client cause)))
                     (is (null (libtmux:error-outcome cause)))
                     (is (not (typep cause 'libtmux:outcome-unknown))))))
               (is (= (ecase phase
                        (:before-fetch 0) ((:reuse :before-first-step :between-steps) 1)
                        (:final-proof 2))
                      fetches))
               (is (= (ecase phase
                        ((:before-fetch :reuse :before-first-step) 0)
                        (:between-steps 2) (:final-proof 5))
                      executions))))
        (libtmux:close-client client)))))

(test workspace-total-budget-validates-before-io
  (let* ((workspace (workspace-call :make-workspace (example-workspace-data)))
         (client (make-instance 'libtmux:client))
         (calls 0)
         (libtmux.workspace::*fetch-snapshot-function*
           (lambda (&rest arguments) (declare (ignore arguments)) (incf calls))))
    (unwind-protect
         (progn
           (dolist (invalid (list nil -1 "1" #C(1 1) (ash 1 4096)))
             (signals libtmux:invalid-argument
               (workspace-call :apply-workspace client workspace :total-timeout invalid)))
           (is (zerop calls)))
      (libtmux:close-client client))))

(defparameter +workspace-creation-json+
  "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"workspace\",\"environment\":{\"APP_VALUE\":\"λ$; value\",\"EMPTY\":\"\"},\"windows\":[{\"name\":\"editor\",\"layout\":{\"custom\":\"layout text\"},\"panes\":[{\"shell_command\":\"exec cat \\\"$APP_VALUE\\\"\"}]}]}}")

(test workspace-json-explicit-inputs-and-environment-limit
  (let* ((workspace (workspace-call :parse-workspace +workspace-creation-json+))
         (data (workspace-call :workspace-data workspace))
         (session (getf data :session))
         (window (aref (getf session :windows) 0)))
    (is (equalp #(("APP_VALUE" . "λ$; value") ("EMPTY" . ""))
                (getf session :environment)))
    (is (equal '(:custom "layout text") (getf window :layout)))
    (is (string= "exec cat \"$APP_VALUE\""
                 (getf (aref (getf window :panes) 0) :shell-command))))
  (handler-case
      (progn
        (workspace-call :parse-workspace +workspace-creation-json+ :max-environment 1)
        (fail "An oversized session environment was accepted"))
    (condition (condition)
      (unless (workspace-condition-p condition :workspace-limit-exceeded)
        (error condition))
      (is (eq :max-environment (workspace-call :workspace-limit condition)))))
  (dolist (environment '("[]" "null" "{\"A\":null}" "{\"A\":\"1\",\"A\":\"2\"}"))
    (signals-workspace :invalid-workspace-document
      (workspace-call :parse-workspace
                      (format nil "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"s\",\"environment\":~A,\"windows\":[{\"name\":\"w\",\"panes\":[{}]}]}}"
                              environment)))))

(test workspace-native-creation-inputs-reject-ambiguity-and-invalid-pairs
  (dolist (pairs '(#(("A" . "1") ("A" . "2")) #(("A=B" . "x"))
                   #(("" . "x")) #(("A" "x")) #(("A" . 1))))
    (let ((data (example-workspace-data)))
      (setf (getf (getf data :session) :environment) pairs)
      (signals-workspace :invalid-workspace (workspace-call :make-workspace data))))
  (signals-workspace :invalid-workspace
    (workspace-call :make-workspace (workspace-creation-inputs) :max-environment 1))
  (dolist (pane '((:command #("/bin/cat") :shell-command "exec cat")
                  (:command nil :shell-command "exec cat")
                  (:shell-command nil) (:shell-command "")
                  (:environment #(("A" . "x")))))
    (let ((data (example-workspace-data)))
      (setf (aref (getf (aref (getf (getf data :session) :windows) 0) :panes) 0)
            pane)
      (signals-workspace :invalid-workspace (workspace-call :make-workspace data))))
  (let ((data (example-workspace-data)))
    (setf (getf (getf data :session) :environment) #())
    (is (typep (workspace-call :make-workspace data :max-environment 0)
               (find-symbol "WORKSPACE" :libtmux.workspace))))
  (dolist (layout '((:custom) (:custom "text" "extra") (:custom "") (:custom 3)))
    (let ((data (example-workspace-data)))
      (setf (getf (aref (getf (getf data :session) :windows) 0) :layout) layout)
      (signals-workspace :invalid-workspace (workspace-call :make-workspace data)))))
