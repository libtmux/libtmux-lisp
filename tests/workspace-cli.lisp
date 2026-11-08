(in-package #:libtmux.tests)

(in-suite workspace)

(defun call-workspace-cli (arguments)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (values (uiop:symbol-call :libtmux.workspace.cli :main :arguments arguments
                              :stdout stdout :stderr stderr)
            (get-output-stream-string stdout)
            (get-output-stream-string stderr))))

(test workspace-cli-validates-and-plans-without-a-daemon
  (let* ((directory (uiop:ensure-directory-pathname
                     (sb-posix:mkdtemp "/tmp/libtmux-workspace-cli-XXXXXX")))
         (path (merge-pathnames "workspace.json" directory))
         (calls 0)
         (libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (incf calls))))
    (unwind-protect
         (progn
           (with-open-file (stream path :direction :output :if-exists :error
                                        :external-format :utf-8)
             (write-string +workspace-json+ stream))
           (multiple-value-bind (code stdout stderr)
               (call-workspace-cli (list "validate" (namestring path)))
             (is (zerop code))
             (is (search "\"status\":\"valid\"" stdout))
             (is (search "\"windows\":2" stdout))
             (is (string= "" stderr)))
           (multiple-value-bind (code stdout stderr)
               (call-workspace-cli (list "plan" (namestring path)))
             (is (zerop code))
             (is (search "\"status\":\"planned\"" stdout))
             (is (search "\"create-session\"" stdout))
             (is (string= "" stderr)))
           (is (zerop calls)))
      (uiop:delete-directory-tree directory :validate t))))

(test workspace-cli-requires-an-explicit-apply-endpoint
  (multiple-value-bind (code stdout stderr)
      (call-workspace-cli '("apply" "workspace.json"))
    (is (= 2 code))
    (is (string= "" stdout))
    (is (search "--socket-path" stderr)))
  (multiple-value-bind (code stdout stderr)
      (call-workspace-cli '("unknown"))
    (is (= 2 code))
    (is (string= "" stdout))
    (is (search "validate" stderr))))

(test workspace-cli-preserves-partial-and-uncertain-outcomes
  (let* ((last (make-instance 'libtmux:command-outcome
                              :status :unknown :phase :dispatched
                              :arguments #("move-window" "-t" "@17")
                              :stdout #() :stderr #(255 10)
                              :reason :deadline :elapsed 0.25))
         (first (make-instance 'libtmux:command-outcome
                               :status :succeeded :phase :exited
                               :arguments #("new-session") :stdout #() :stderr #()
                               :exit-code 0 :elapsed 0.0
                               :observation-error
                               (make-condition 'libtmux:incomplete-snapshot
                                               :message "Capture failed" :outcome last)))
         (cause (make-condition 'libtmux:outcome-unknown
                                :message "Dispatch timed out" :outcome last))
         (failure (make-condition 'libtmux.workspace:workspace-apply-failed
                                  :message "Workspace application stopped"
                                  :cause cause :outcomes (vector first last)
                                  :step (libtmux.workspace::make-step
                                         :move-window :window-name "code" :index 2)))
         (symbol (find-symbol "RUN-COMMAND" :libtmux.workspace.cli))
         (original (symbol-function symbol)))
    (unwind-protect
         (progn
           (setf (symbol-function symbol)
                 (lambda (arguments stdout)
                   (declare (ignore arguments stdout))
                   (error failure)))
           (multiple-value-bind (code stdout stderr) (call-workspace-cli '("apply"))
             (is (= 1 code))
             (is (string= "" stdout))
             (is (and (plusp (length stderr)) (char= #\{ (char stderr 0))))
             (when (and (plusp (length stderr)) (char= #\{ (char stderr 0)))
               (let* ((document (com.inuoe.jzon:parse stderr))
                      (outcomes (gethash "outcomes" document))
                      (step (gethash "failedStep" document)))
                 (is (string= "error" (gethash "status" document)))
                 (is (string= "workspace-apply-failed" (gethash "condition" document)))
                 (is (= 2 (length outcomes)))
                 (is (string= "succeeded" (gethash "status" (aref outcomes 0))))
                 (is (= 0 (gethash "exitCode" (aref outcomes 0))))
                 (let ((capture (gethash "outcome"
                                         (gethash "observationError" (aref outcomes 0)))))
                   (is (and capture (string= "unknown" (gethash "status" capture)))))
                 (is (string= "unknown" (gethash "status" (aref outcomes 1))))
                 (is (string= "dispatched" (gethash "phase" (aref outcomes 1))))
                 (is (equalp #("move-window" "-t" "@17")
                             (gethash "arguments" (aref outcomes 1))))
                 (is (equalp #(255 10) (gethash "stderrBytes" (aref outcomes 1))))
                 (is (string= "deadline" (gethash "reason" (aref outcomes 1))))
                 (is (string= "move-window" (gethash "action" step)))
                 (is (= 2 (gethash "index" (gethash "data" step))))
                 (is (string= "outcome-unknown"
                              (gethash "condition" (gethash "cause" document))))))))
      (setf (symbol-function symbol) original))))

(test workspace-cli-preserves-nested-validation-paths
  (let* ((condition
           (handler-case
               (workspace-call
                :parse-workspace
                "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"bad\",\"windows\":[{\"name\":\"main\",\"index\":-1,\"panes\":[{}]}]}}")
             (libtmux.workspace:invalid-workspace-document (condition) condition)))
         (stream (make-string-output-stream)))
    (uiop:symbol-call :libtmux.workspace.cli :write-failure stream condition)
    (let ((document (com.inuoe.jzon:parse (get-output-stream-string stream))))
      (is (equalp #("session" "windows" 0 "index")
                  (gethash "path" (gethash "cause" document)))))))
