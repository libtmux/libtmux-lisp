(defpackage #:libtmux.workspace.cli
  (:use #:cl)
  (:documentation "Command-line adapter for bounded libtmux workspace documents.
VALIDATE and v1 offline PLAN are local. Owned PLAN, INSPECT and APPLY require an
explicit socket path and use a scoped libtmux client. Output is one JSON summary;
failures return a nonzero status without entering the debugger.")
  (:export #:main))

(in-package #:libtmux.workspace.cli)

(define-condition cli-usage-error (error)
  ((message :initarg :message :reader cli-usage-message)))

(defun usage (stream)
  (write-string
   "Usage:
  libtmux-workspace validate FILE
  libtmux-workspace plan FILE [--socket-path PATH] [--program PROGRAM] [--reconcile]
  libtmux-workspace apply FILE --socket-path PATH [--program PROGRAM] [--reconcile]
  libtmux-workspace inspect FILE --socket-path PATH [--program PROGRAM]

Only workspace/1 supports offline plan. Endpoint plan acquires fresh state.
--reconcile permits owned workspace/2 plan/apply; previews grant no authority.
"
   stream))

(defun usage-error (control &rest arguments)
  (error 'cli-usage-error :message (apply #'format nil control arguments)))

(defun exact-arguments (arguments count command)
  (unless (= count (length arguments))
    (usage-error "~A expects exactly ~D argument~:P" command count))
  arguments)

(defun action-name (action)
  (string-downcase (symbol-name action)))

(defun workspace-summary (workspace)
  (let* ((data (libtmux.workspace:workspace-data workspace))
         (session (getf data :session))
         (windows (getf session :windows)))
    (values (getf session :name) (length windows)
            (loop for window across windows sum (length (getf window :panes))))))

(defun write-validation (stream workspace)
  (let ((data (libtmux.workspace:workspace-data workspace)))
    (multiple-value-bind (session windows panes) (workspace-summary workspace)
      (com.inuoe.jzon:with-writer (writer :stream stream :max-depth nil)
        (com.inuoe.jzon:with-object writer
          (com.inuoe.jzon:write-key writer "status")
          (com.inuoe.jzon:write-value writer "valid")
          (com.inuoe.jzon:write-key writer "schema")
          (com.inuoe.jzon:write-value writer (getf data :schema))
          (when (getf data :id)
            (com.inuoe.jzon:write-key writer "id")
            (com.inuoe.jzon:write-value writer (getf data :id)))
          (com.inuoe.jzon:write-key writer "session")
          (com.inuoe.jzon:write-value writer session)
          (com.inuoe.jzon:write-key writer "windows")
          (com.inuoe.jzon:write-value writer windows)
          (com.inuoe.jzon:write-key writer "panes")
          (com.inuoe.jzon:write-value writer panes)))))
  (terpri stream))

(defparameter *owned-json-fields*
  '(:status :phase :step :initial-plan :plan :mappings :session-id :windows
    :selected-state :candidate :observed-state :record :writer
    :publication-status :publication-reason :stage :head :control-key :control
    :pending :schema :workspace :base :declaration :session :id :name :cwd
    :environment :command :shell-command :panes :index :layout :daemon :revision
    :previous :bytes :chunks :logical-id :physical-id :window-id :pane-id
    :session-name :window-name :pane-position :direction :target :before-pane-id :anchor-id
    :links :context :generation :witness :committed
    :headers :inventory :groups :geometry :read-restarts :acquired-start :acquired-end
    :pid :start :process-start :device :inode :version :complete-p :attempts
    :opening-control :closing-control :opening-inventory :closing-inventory
    :roles :diagnostics :role :kind :header :message :changes :drift :conflicts
    :publish-p :path :before :after :reason :present-p :value :regular-p :zoomed-p
    :floating-p :modal-p :server/pid :server/start-time :server/socket-path
    :server/version :server/socket-device :server/socket-inode :server/process-start))

(defparameter *owned-json-booleans*
  '(:publish-p :complete-p :present-p :regular-p :zoomed-p :floating-p :modal-p :grouped-p))

(defun owned-json-value (value &optional field step-action)
  "Convert finite owned diagnostic data without serializing arbitrary Lisp objects."
  (labels
      ((convert (value field parents depth &optional boolean-p)
         (when (> depth 64) (error "Workspace diagnostic nesting exceeds 64 levels"))
         (cond
           ((null value) (if (or boolean-p (member field *owned-json-booleans*)) nil 'null))
           ((eq value t) t)
           ((stringp value) value)
           ((integerp value) value)
           ((realp value) (coerce value 'double-float))
           ((keywordp value) (action-name value))
           ((or (consp value) (vectorp value))
            (when (member value parents :test #'eq) (error "Cyclic workspace diagnostic data"))
            (let ((parents (cons value parents)))
              (cond
                ((and (member field '(:environment :groups)) (vectorp value))
                 (let ((object (make-hash-table :test #'equal)))
                   (loop for pair across value
                         do (unless (and (consp pair) (stringp (car pair)))
                              (error "Invalid workspace diagnostic association"))
                            (setf (gethash (car pair) object)
                                  (convert (cdr pair) (when (eq field :groups) :grouped-p)
                                           parents (1+ depth))))
                   object))
                ((vectorp value)
                 (map 'simple-vector (lambda (item) (convert item nil parents (1+ depth))) value))
                ((and (stringp (car value)) (atom (cdr value)) (cdr value))
                 (vector (car value) (convert (cdr value) nil parents (1+ depth))))
                (t
                 (let ((length (list-length value)))
                   (unless length (error "Cyclic workspace diagnostic list"))
                   (if (and (keywordp (car value)) (not (eq field :role))
                            (not (eq (car value) :custom)))
                       (let ((object (make-hash-table :test #'equal)))
                         (unless (evenp length) (error "Invalid workspace diagnostic object"))
                         (loop for (key item) on value by #'cddr
                               do (unless (member key *owned-json-fields*)
                                    (error "Unknown workspace diagnostic field ~S" key))
                                  (setf (gethash (action-name key) object)
                                        (convert item key parents (1+ depth)
                                                 (and (eq key :before)
                                                      (or (eq field :step)
                                                          (and (zerop depth)
                                                               (eq step-action :split-pane)))))))
                         object)
                       (map 'simple-vector (lambda (item) (convert item nil parents (1+ depth))) value)))))))
           (t (error "Unsupported workspace diagnostic type ~S" (type-of value))))))
    (convert value field nil 0)))

(defun write-owned-member (writer name data &optional step-action)
  (com.inuoe.jzon:write-key writer name)
  (com.inuoe.jzon:write-value writer (owned-json-value data nil step-action)))

(defun write-causes (writer name causes depth)
  (com.inuoe.jzon:write-key writer name)
  (com.inuoe.jzon:with-array writer
    (loop for cause across causes
          do (com.inuoe.jzon:with-object writer
               (write-condition-fields writer cause (1+ depth))))))

(defun write-outcomes (writer name outcomes depth)
  (com.inuoe.jzon:write-key writer name)
  (com.inuoe.jzon:with-array writer
    (loop for outcome across outcomes do (write-outcome writer outcome (1+ depth)))))

(defun write-plan (stream plan)
  (let ((steps (libtmux.workspace:plan-steps plan)))
    (com.inuoe.jzon:with-writer (writer :stream stream :max-depth nil)
      (com.inuoe.jzon:with-object writer
        (com.inuoe.jzon:write-key writer "status")
        (com.inuoe.jzon:write-value writer "planned")
        (com.inuoe.jzon:write-key writer "steps")
        (com.inuoe.jzon:write-value writer (length steps))
        (com.inuoe.jzon:write-key writer "actions")
        (com.inuoe.jzon:with-array writer
          (loop for step across steps
                do (com.inuoe.jzon:write-value
                    writer (action-name (libtmux.workspace:step-action step)))))
        (multiple-value-bind (data present-p) (libtmux.workspace:plan-data plan)
          (when present-p (write-owned-member writer "data" data))))))
  (terpri stream))

(defun write-application (stream workspace result)
  (multiple-value-bind (session windows panes) (workspace-summary workspace)
    (com.inuoe.jzon:with-writer (writer :stream stream :max-depth nil)
      (com.inuoe.jzon:with-object writer
        (com.inuoe.jzon:write-key writer "status")
        (com.inuoe.jzon:write-value writer "applied")
        (com.inuoe.jzon:write-key writer "session")
        (com.inuoe.jzon:write-value writer session)
        (com.inuoe.jzon:write-key writer "created")
        (com.inuoe.jzon:write-value writer
                                    (not (null (libtmux.workspace:result-created-p result))))
        (com.inuoe.jzon:write-key writer "outcomes")
        (com.inuoe.jzon:write-value
         writer (length (libtmux.workspace:result-outcomes result)))
        (com.inuoe.jzon:write-key writer "windows")
        (com.inuoe.jzon:write-value writer windows)
        (com.inuoe.jzon:write-key writer "panes")
        (com.inuoe.jzon:write-value writer panes)
        (multiple-value-bind (data present-p) (libtmux.workspace:result-data result)
          (when present-p
            (write-owned-member writer "data" data)
            (write-outcomes writer "commandOutcomes" (libtmux.workspace:result-outcomes result) 0)
            (write-causes writer "causes" (libtmux.workspace:result-causes result) 0))))))
  (terpri stream))

(defun write-inspection-fields (writer inspection &optional (depth 0))
  (write-owned-member writer "data" (libtmux.workspace:inspection-data inspection))
  (write-outcomes writer "outcomes" (libtmux.workspace:inspection-outcomes inspection) depth)
  (write-causes writer "causes" (libtmux.workspace:inspection-causes inspection) depth))

(defun write-inspection (stream inspection)
  (com.inuoe.jzon:with-writer (writer :stream stream :max-depth nil)
    (com.inuoe.jzon:with-object writer
      (com.inuoe.jzon:write-key writer "status")
      (com.inuoe.jzon:write-value writer "inspected")
      (write-inspection-fields writer inspection)))
  (terpri stream))

(defun write-condition-fields (writer condition &optional (depth 0))
  (com.inuoe.jzon:write-key writer "condition")
  (com.inuoe.jzon:write-value writer (string-downcase (symbol-name (type-of condition))))
  (com.inuoe.jzon:write-key writer "message")
  (com.inuoe.jzon:write-value
   writer (if (typep condition 'libtmux:libtmux-error)
              (libtmux:error-message condition)
              (princ-to-string condition)))
  (if (>= depth 8)
      (progn
        (com.inuoe.jzon:write-key writer "detailsTruncated")
        (com.inuoe.jzon:write-value writer t))
      (progn
        (when (typep condition 'libtmux.workspace:workspace-error)
          (com.inuoe.jzon:write-key writer "path")
          (com.inuoe.jzon:write-value
           writer (diagnostic-value (libtmux.workspace:workspace-path condition)))
          (when (libtmux.workspace:workspace-limit condition)
            (com.inuoe.jzon:write-key writer "limit")
            (com.inuoe.jzon:write-value
             writer (action-name (libtmux.workspace:workspace-limit condition)))))
        (when (typep condition 'libtmux.workspace:workspace-apply-failed)
          (let ((step (libtmux.workspace:failed-step condition)))
            (when step
              (com.inuoe.jzon:write-key writer "failedStep")
              (com.inuoe.jzon:with-object writer
                (com.inuoe.jzon:write-key writer "action")
                (com.inuoe.jzon:write-value
                 writer (action-name (libtmux.workspace:step-action step)))
                (write-owned-member writer "data" (libtmux.workspace:step-data step)
                                    (libtmux.workspace:step-action step)))))
          (write-outcomes writer "outcomes" (libtmux.workspace:result-outcomes condition) depth)
          (multiple-value-bind (data present-p) (libtmux.workspace:result-data condition)
            (when present-p
              (write-owned-member writer "data" data)
              (write-causes writer "causes" (libtmux.workspace:result-causes condition) depth))))
        (when (typep condition 'libtmux.workspace:workspace-conflict)
          (multiple-value-bind (data present-p) (libtmux.workspace:plan-data condition)
            (when present-p (write-owned-member writer "plan" data))))
        (when (typep condition 'libtmux.workspace:workspace-state-error)
          (write-owned-member writer "state" (libtmux.workspace:state-data condition))
          (write-outcomes writer "outcomes" (libtmux.workspace:state-outcomes condition) depth)
          (write-causes writer "causes" (libtmux.workspace:state-causes condition) depth))
        (when (typep condition 'libtmux.workspace:workspace-inspection-error)
          (com.inuoe.jzon:write-key writer "inspection")
          (com.inuoe.jzon:with-object writer
            (write-inspection-fields writer (libtmux.workspace:inspection-evidence condition) depth))
          (com.inuoe.jzon:write-key writer "terminal")
          (com.inuoe.jzon:with-object writer
            (write-condition-fields writer (libtmux.workspace:inspection-terminal condition) (1+ depth))))
        (when (typep condition 'libtmux:libtmux-error)
          (let ((outcome (libtmux:error-outcome condition))
                (cause (libtmux:error-cause condition)))
            (when outcome
              (com.inuoe.jzon:write-key writer "outcome")
              (write-outcome writer outcome (1+ depth)))
            (when cause
              (com.inuoe.jzon:write-key writer "cause")
              (com.inuoe.jzon:with-object writer
                (write-condition-fields writer cause (1+ depth)))))))))

(defun write-outcome (writer outcome &optional (depth 0))
  (com.inuoe.jzon:with-object writer
    (loop for key in '("status" "phase")
          for value in (list (libtmux:outcome-status outcome)
                             (libtmux:outcome-phase outcome))
          do (com.inuoe.jzon:write-key writer key)
             (com.inuoe.jzon:write-value writer (action-name value)))
    (com.inuoe.jzon:write-key writer "arguments")
    (com.inuoe.jzon:write-value writer (libtmux:outcome-arguments outcome))
    (com.inuoe.jzon:write-key writer "elapsedSeconds")
    (com.inuoe.jzon:write-value writer (libtmux:outcome-elapsed outcome))
    (loop for key in '("stdoutBytes" "stderrBytes")
          for bytes in (list (libtmux:outcome-stdout outcome)
                             (libtmux:outcome-stderr outcome))
          do (com.inuoe.jzon:write-key writer key)
             (com.inuoe.jzon:write-value writer bytes))
    (let ((exit-code (libtmux:outcome-exit-code outcome))
          (reason (libtmux:outcome-reason outcome))
          (observation-error (libtmux:outcome-observation-error outcome))
          (cleanup-failures (libtmux:outcome-cleanup-failures outcome)))
      (when exit-code
        (com.inuoe.jzon:write-key writer "exitCode")
        (com.inuoe.jzon:write-value writer exit-code))
      (when reason
        (com.inuoe.jzon:write-key writer "reason")
        (com.inuoe.jzon:write-value writer (action-name reason)))
      (when observation-error
        (com.inuoe.jzon:write-key writer "observationError")
        (com.inuoe.jzon:with-object writer
          (write-condition-fields writer observation-error (1+ depth))))
      (when (plusp (length cleanup-failures))
        (com.inuoe.jzon:write-key writer "cleanupFailures")
        (com.inuoe.jzon:with-array writer
          (loop for condition across cleanup-failures
                do (com.inuoe.jzon:with-object writer
                     (write-condition-fields writer condition (1+ depth)))))))))

(defun diagnostic-value (value)
  (typecase value
    (keyword (action-name value))
    (string value)
    (vector (map 'simple-vector #'diagnostic-value value))
    (t value)))

(defun write-failure (stream condition)
  (com.inuoe.jzon:with-writer (writer :stream stream :max-depth nil)
    (com.inuoe.jzon:with-object writer
      (com.inuoe.jzon:write-key writer "status")
      (com.inuoe.jzon:write-value writer "error")
      (write-condition-fields writer condition)))
  (terpri stream))

(defun command-options (command arguments)
  (unless arguments (usage-error "~A requires FILE and an explicit --socket-path when acquiring" command))
  (let ((file (first arguments)) (options (rest arguments))
        (socket nil) (program "tmux") (reconcile nil) (seen nil))
    (when (or (zerop (length file)) (and (>= (length file) 2) (string= file "--" :end1 2)))
      (usage-error "~A requires FILE before its options" command))
    (loop while options
          for name = (pop options)
          do (when (member name seen :test #'string=)
               (usage-error "~A option ~A occurs more than once" command name))
             (push name seen)
             (cond
               ((string= name "--reconcile")
                (unless (member command '("plan" "apply") :test #'string=)
                  (usage-error "--reconcile is only valid for plan and apply"))
                (setf reconcile t))
               ((member name '("--socket-path" "--program") :test #'string=)
                (let ((value (pop options)))
                  (unless (and value (plusp (length value))
                               (not (and (>= (length value) 2) (string= value "--" :end1 2))))
                    (usage-error "~A requires a value" name))
                  (if (string= name "--socket-path") (setf socket value) (setf program value))))
               (t (usage-error "unknown ~A option ~A" command name))))
    (when (and (member "--program" seen :test #'string=) (null socket))
      (usage-error "--program requires --socket-path PATH"))
    (when (and (member command '("apply" "inspect") :test #'string=) (null socket))
      (usage-error "~A requires --socket-path PATH" command))
    (values file socket program reconcile)))

(defun owned-workspace-p (workspace)
  (string= "libtmux.lisp.workspace/2" (getf (libtmux.workspace:workspace-data workspace) :schema)))

(defun check-workspace-mode (command workspace socket reconcile)
  (let ((owned-p (owned-workspace-p workspace)))
    (when (and reconcile (not owned-p)) (usage-error "--reconcile requires workspace/2"))
    (when (and (string= command "inspect") (not owned-p)) (usage-error "inspect requires workspace/2"))
    (when (and owned-p (string= command "plan") (null socket))
      (usage-error "workspace/2 plan requires --socket-path PATH"))))

(defun run-command (arguments stdout)
  (unless arguments (usage-error "a command is required"))
  (let ((command (first arguments)) (rest (rest arguments)))
    (cond
      ((member command '("--help" "-h") :test #'string=)
       (exact-arguments rest 0 command)
       (usage stdout)
       0)
      ((string= command "validate")
       (exact-arguments rest 1 command)
       (write-validation stdout (libtmux.workspace:read-workspace (command-options command rest)))
       0)
      ((string= command "plan")
       (multiple-value-bind (file socket program reconcile) (command-options command rest)
         (let ((workspace (libtmux.workspace:read-workspace file)))
           (check-workspace-mode command workspace socket reconcile)
           (if socket
               (libtmux:with-client (client :program program :socket-path socket)
                 (write-plan stdout
                             (libtmux.workspace:plan-workspace
                              workspace (if (owned-workspace-p workspace)
                                            (libtmux.workspace:fetch-workspace-state client workspace)
                                            (libtmux:fetch-snapshot client))
                              :reconcile reconcile)))
               (write-plan stdout (libtmux.workspace:plan-workspace workspace)))))
       0)
      ((string= command "apply")
       (multiple-value-bind (file socket program reconcile) (command-options command rest)
         (let ((workspace (libtmux.workspace:read-workspace file)))
           (check-workspace-mode command workspace socket reconcile)
           (libtmux:with-client (client :program program :socket-path socket)
             (write-application
              stdout workspace
              (libtmux.workspace:apply-workspace client workspace :reconcile reconcile)))))
       0)
      ((string= command "inspect")
       (multiple-value-bind (file socket program reconcile) (command-options command rest)
         (let ((workspace (libtmux.workspace:read-workspace file)))
           (check-workspace-mode command workspace socket reconcile)
           (libtmux:with-client (client :program program :socket-path socket)
             (write-inspection stdout (libtmux.workspace:inspect-workspace client workspace)))))
       0)
      (t (usage-error "unknown command ~A" command)))))

(defun main (&key (arguments (uiop:command-line-arguments))
                  (stdout *standard-output*) (stderr *error-output*))
  "Run the workspace CLI for ARGUMENTS and return process status 0, 1, or 2.
VALIDATE is local. PLAN without an endpoint is local and requires workspace/1;
endpoint PLAN reads a snapshot or owned state before producing a local preview.
APPLY and owned-only INSPECT require --socket-path. --program selects the native
executable. The standalone --reconcile flag is owned-only for PLAN and APPLY.
Options and schema misuse fail before opening a client. The scoped client closes
without terminating the server. STDOUT receives one JSON result or help.
STDERR receives usage text or one JSON error retaining condition causes, failed
step data, and command outcomes, including byte arrays and unknown dispatch
status. An unavailable exit code or failed step is omitted. MAIN does not call
UIOP:QUIT, close caller streams, or enter the debugger.
Owned summaries add DATA with native lowercase keyword names. Vectors are arrays,
Boolean fields preserve false and absent optional values become null. Environment
and session-group associations are objects. Native snapshots are not serialized.
Completed INSPECT returns 0 even for busy or invalid ownership; DATA's COMPLETE-P
describes read completion, not readiness. Failed inspection retains its partial
data and original/terminal causes. Nested condition details stop after eight
levels and mark detailsTruncated. No command is automatically retried.

See also: APPLY-WORKSPACE, LIBTMUX:OUTCOME-STATUS, LIBTMUX:OUTCOME-PHASE."
  (handler-case
      (run-command arguments stdout)
    (cli-usage-error (condition)
      (format stderr "libtmux-workspace: ~A~%" (cli-usage-message condition))
      (usage stderr)
      2)
    (libtmux:libtmux-error (condition)
      (write-failure stderr condition)
      1)
    (error (condition)
      (write-failure stderr condition)
      1)))
