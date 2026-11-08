(defpackage #:libtmux.workspace.cli
  (:use #:cl)
  (:documentation "Command-line adapter for bounded libtmux workspace documents.
VALIDATE and PLAN are local. APPLY requires an explicit socket path and uses a
scoped libtmux client. Output is one JSON summary; failures return a nonzero
status without entering the debugger.")
  (:export #:main))

(in-package #:libtmux.workspace.cli)

(define-condition cli-usage-error (error)
  ((message :initarg :message :reader cli-usage-message)))

(defun usage (stream)
  (write-string
   "Usage:
  libtmux-workspace validate FILE
  libtmux-workspace plan FILE
  libtmux-workspace apply FILE --socket-path PATH [--program PROGRAM]
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
  (multiple-value-bind (session windows panes) (workspace-summary workspace)
    (com.inuoe.jzon:with-writer (writer :stream stream :max-depth nil)
      (com.inuoe.jzon:with-object writer
        (com.inuoe.jzon:write-key writer "status")
        (com.inuoe.jzon:write-value writer "valid")
        (com.inuoe.jzon:write-key writer "schema")
        (com.inuoe.jzon:write-value writer "libtmux.lisp.workspace/1")
        (com.inuoe.jzon:write-key writer "session")
        (com.inuoe.jzon:write-value writer session)
        (com.inuoe.jzon:write-key writer "windows")
        (com.inuoe.jzon:write-value writer windows)
        (com.inuoe.jzon:write-key writer "panes")
        (com.inuoe.jzon:write-value writer panes))))
  (terpri stream))

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
                    writer (action-name (libtmux.workspace:step-action step))))))))
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
        (com.inuoe.jzon:write-value writer panes))))
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
                (com.inuoe.jzon:write-key writer "data")
                (com.inuoe.jzon:with-object writer
                  (loop for (key value) on (libtmux.workspace:step-data step) by #'cddr
                        do (com.inuoe.jzon:write-key writer (action-name key))
                           (com.inuoe.jzon:write-value writer (diagnostic-value value)))))))
          (com.inuoe.jzon:write-key writer "outcomes")
          (com.inuoe.jzon:with-array writer
            (loop for outcome across (libtmux.workspace:result-outcomes condition)
                  do (write-outcome writer outcome (1+ depth)))))
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

(defun apply-options (arguments)
  (unless arguments (usage-error "apply requires FILE and --socket-path PATH"))
  (let ((file (first arguments)) (rest (rest arguments))
        (socket nil) (program "tmux") (seen nil))
    (unless (evenp (length rest))
      (usage-error "apply options require names and values"))
    (loop for (name value) on rest by #'cddr
          do (when (member name seen :test #'string=)
               (usage-error "apply option ~A occurs more than once" name))
             (push name seen)
             (cond ((string= name "--socket-path") (setf socket value))
                   ((string= name "--program") (setf program value))
                   (t (usage-error "unknown apply option ~A" name))))
    (unless socket (usage-error "apply requires --socket-path PATH"))
    (values file socket program)))

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
       (write-validation stdout (libtmux.workspace:read-workspace (first rest)))
       0)
      ((string= command "plan")
       (exact-arguments rest 1 command)
       (write-plan stdout
                   (libtmux.workspace:plan-workspace
                    (libtmux.workspace:read-workspace (first rest))))
       0)
      ((string= command "apply")
       (multiple-value-bind (file socket program) (apply-options rest)
         (let ((workspace (libtmux.workspace:read-workspace file)))
           (libtmux:with-client (client :program program :socket-path socket)
             (write-application
              stdout workspace
              (libtmux.workspace:apply-workspace client workspace)))))
       0)
      (t (usage-error "unknown command ~A" command)))))

(defun main (&key (arguments (uiop:command-line-arguments))
                  (stdout *standard-output*) (stderr *error-output*))
  "Run the workspace CLI for ARGUMENTS and return process status 0, 1, or 2.
VALIDATE and PLAN parse one bounded file without tmux I/O. APPLY requires
--socket-path and optionally accepts --program; it scopes and closes its own
client without terminating the server. STDOUT receives one JSON result or help.
STDERR receives usage text or one JSON error retaining condition causes, failed
step data, and command outcomes, including byte arrays and unknown dispatch
status. An unavailable exit code or failed step is omitted. MAIN does not call
UIOP:QUIT, close caller streams, or enter the debugger.
Nested diagnostic details stop after eight levels and mark detailsTruncated.

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
