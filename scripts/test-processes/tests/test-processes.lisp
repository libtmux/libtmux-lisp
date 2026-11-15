(in-package #:libtmux.tests)

(in-suite scripts)

(defun supervise-command (&rest command)
  "Run the supervisor on COMMAND; return its exit code and standard error."
  (multiple-value-bind (code output error-output)
      (libtmux.scripts:run
       (list* "sbcl" "--script"
              (uiop:native-namestring
               (asdf:system-relative-pathname
                "libtmux" "scripts/test-processes/test-processes.lisp"))
              command)
       :check nil)
    (declare (ignore output))
    (values code error-output)))

(test supervisor-passes-a-clean-command-through
  (multiple-value-bind (code message) (supervise-command "true")
    (is (eql 0 code))
    (is (string= "" message))))

(test supervisor-reports-the-childs-status-as-its-own
  (multiple-value-bind (code message) (apply #'supervise-command (child-command "exit" "7"))
    (is (eql 7 code))
    (is (search "Owned child exited 7; descendant cleanup: PASS" message))))

(test supervisor-kills-and-counts-an-orphaned-descendant
  (multiple-value-bind (code message) (apply #'supervise-command (child-command "inherited-pipes"))
    (is (eql 1 code))
    (is (search "1 owned descendants survived the test image" message))))
