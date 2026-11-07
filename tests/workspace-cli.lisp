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
