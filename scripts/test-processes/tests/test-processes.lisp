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

(test supervisor-clears-ambient-selectors-and-blank-test-tmux
  (let ((script (uiop:native-namestring
                 (asdf:system-relative-pathname
                  "libtmux" "scripts/test-processes/test-processes.lisp")))
        (probe (child-command "context" "TMUX" "TMUX_PANE"
                              "LIBTMUX_SOCKET" "LIBTMUX_SOCKET_PATH" "LIBTMUX_TEST_TMUX")))
    (multiple-value-bind (code stdout stderr)
        (libtmux.scripts:run
         (list* "sbcl" "--script" script probe)
         :environment (libtmux.scripts:merge-environment
                       "TMUX" "/ambient/sock,1,0" "TMUX_PANE" "%9"
                       "LIBTMUX_SOCKET" "ambient" "LIBTMUX_SOCKET_PATH" "/ambient/path"
                       "LIBTMUX_TEST_TMUX" (format nil " ~C " #\Tab)))
      (is (eql 0 code))
      (is (string= "" stderr))
      (is (equal '("<absent>" "<absent>" "<absent>" "<absent>" "<absent>")
                 (butlast (uiop:split-string stdout :separator '(#\Null))))))
    (multiple-value-bind (code stdout stderr)
        (libtmux.scripts:run
         (list* "sbcl" "--script" script probe)
         :environment (libtmux.scripts:merge-environment
                       "LIBTMUX_SOCKET" "ambient" "LIBTMUX_TEST_TMUX" "/custom/tmux"))
      (is (eql 0 code))
      (is (string= "" stderr))
      (is (equal '("<absent>" "<absent>" "<absent>" "<absent>" "/custom/tmux")
                 (butlast (uiop:split-string stdout :separator '(#\Null))))))))
