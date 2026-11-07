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
STDERR receives concise usage or condition diagnostics. MAIN does not call
UIOP:QUIT, close caller streams, or enter the debugger.

Related functions: LIBTMUX.WORKSPACE:READ-WORKSPACE,
LIBTMUX.WORKSPACE:PLAN-WORKSPACE, and LIBTMUX.WORKSPACE:APPLY-WORKSPACE."
  (handler-case
      (run-command arguments stdout)
    (cli-usage-error (condition)
      (format stderr "libtmux-workspace: ~A~%" (cli-usage-message condition))
      (usage stderr)
      2)
    (libtmux:libtmux-error (condition)
      (format stderr "libtmux-workspace: ~A~%" (libtmux:error-message condition))
      1)
    (error (condition)
      (format stderr "libtmux-workspace: ~A~%" condition)
      1)))
