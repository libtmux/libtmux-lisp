(in-package #:libtmux.tests)

(in-suite workspace)

(defun public-owned-workspace-data ()
  (list :schema "libtmux.lisp.workspace/2" :id "public"
        :session (list :id "main" :name "public-owned"
                       :environment (vector (cons "OWNED_VALUE" "λ"))
                       :windows (vector (list :id "first" :name "same" :index 0
                                              :panes (vector (list :id "first" :command (vector "/bin/cat"))))
                                        (list :id "second" :name "same"
                                              :panes (vector (list :id "second" :shell-command "exec cat")))))))

(test public-workspace-constructor-selects-owned-semantics-and-owns-its-data
  (let* ((input (public-owned-workspace-data))
         (libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (error "Construction contacted tmux")))
         (workspace (libtmux.workspace:make-workspace input))
         (data (libtmux.workspace:workspace-data workspace)))
    (is (typep workspace 'libtmux.workspace:workspace))
    (is (string= "libtmux.lisp.workspace/2" (getf data :schema)))
    (is (string= "public" (getf data :id)))
    (is (= 2 (length (getf (getf data :session) :windows))))
    (setf (char (getf data :id) 0) #\X
          (aref (getf (aref (getf (getf input :session) :windows) 0) :panes) 0) '(:id "changed"))
    (let ((retained (libtmux.workspace:workspace-data workspace)))
      (is (string= "public" (getf retained :id)))
      (is (string= "first" (getf (aref (getf (aref (getf (getf retained :session) :windows) 0) :panes) 0) :id))))))

(test public-owned-workspace-keeps-caller-topology-and-command-bounds
  (dolist (options '((:max-windows 1) (:max-panes 1) (:max-argv 0) (:max-environment 0)))
    (signals libtmux.workspace:invalid-workspace
      (apply #'libtmux.workspace:make-workspace (public-owned-workspace-data) options))))

(test public-workspace-validates-schema-before-version-specific-members
  (dolist (data '((:schema "unknown" :extension 1) (:extension 1)))
    (handler-case
        (progn (libtmux.workspace:make-workspace data) (fail "Unknown schema was accepted"))
      (libtmux.workspace:invalid-workspace (condition)
        (is (equalp #(:schema) (libtmux.workspace:workspace-path condition)))))))

(defun public-owned-workspace-json ()
  (copy-seq "{\"schema\":\"libtmux.lisp.workspace/2\",\"id\":\"public\",\"session\":{\"id\":\"main\",\"name\":\"public-owned\",\"environment\":{\"OWNED_VALUE\":\"λ\"},\"windows\":[{\"id\":\"first\",\"name\":\"same\",\"index\":0,\"panes\":[{\"id\":\"first\",\"command\":[\"/bin/cat\"]}]},{\"id\":\"second\",\"name\":\"same\",\"panes\":[{\"id\":\"second\",\"shell_command\":\"exec cat\"}]}]}}"))

(test public-owned-workspace-json-is-local-and-retains-its-declared-identities
  (let* ((libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (error "Parsing contacted tmux")))
         (source (public-owned-workspace-json))
         (workspace (libtmux.workspace:parse-workspace source))
         (data (libtmux.workspace:workspace-data workspace)))
    (is (string= "public" (getf data :id)))
    (is (= 2 (length (getf (getf data :session) :windows))))
    (is (string= "exec cat" (getf (aref (getf (aref (getf (getf data :session) :windows) 1) :panes) 0) :shell-command)))
    (setf (char source 0) #\X (char (getf data :id) 0) #\X)
    (is (string= "public" (getf (libtmux.workspace:workspace-data workspace) :id)))))

(test public-owned-workspace-json-preserves-tightened-caller-limits
  (dolist (spec '((:max-windows 1) (:max-panes 1) (:max-argv 0) (:max-environment 0)
                  (:max-input-bytes 8) (:max-depth 2) (:max-nodes 3)
                  (:max-string-length 10) (:max-integer-digits 0)))
    (handler-case
        (progn (apply #'libtmux.workspace:parse-workspace (public-owned-workspace-json) spec)
               (fail "A tightened public JSON limit was ignored"))
      (libtmux.workspace:invalid-workspace-document (condition)
        (is (eq (first spec) (libtmux.workspace:workspace-limit condition)))))))

(test public-owned-reads-reject-legacy-data-and-invalid-limits-before-io
  (let ((fetch (public-workspace-function :fetch-workspace-state))
        (inspect (public-workspace-function :inspect-workspace))
        (legacy (libtmux.workspace:make-workspace (example-workspace-data)))
        (owned (libtmux.workspace:make-workspace (public-owned-workspace-data)))
        (client (make-instance 'libtmux:client)))
    (unwind-protect
         (let ((libtmux.internal::*process-launched-hook*
                 (lambda (job) (declare (ignore job)) (error "Invalid read options contacted tmux"))))
           (dolist (function (list fetch inspect))
             (signals libtmux.workspace:invalid-workspace (funcall function client legacy))
             (dolist (limit '(0 100001 1.5))
               (signals libtmux.workspace:invalid-workspace (funcall function client owned :record-limit limit)))))
      (libtmux:close-client client))))

(test public-workspace-evidence-preserves-legacy-absence-values
  (let* ((plan-data (public-workspace-function :plan-data))
         (result-data (public-workspace-function :result-data))
         (result-causes (public-workspace-function :result-causes))
         (workspace (libtmux.workspace:make-workspace (example-workspace-data)))
         (plan (libtmux.workspace:plan-workspace workspace))
         (result (make-instance 'libtmux.workspace:workspace-result :snapshot nil :outcomes #() :created-p nil))
         (failure (make-condition 'libtmux.workspace:workspace-apply-failed :message "Unobserved legacy failure")))
    (is (equal '(nil nil) (multiple-value-list (funcall plan-data plan))))
    (is (equal '(nil nil) (multiple-value-list (funcall result-data result))))
    (is (equal '(nil nil) (multiple-value-list (funcall result-data failure))))
    (is (null (libtmux.workspace:result-snapshot failure)))
    (is (zerop (length (funcall result-causes failure))))))
