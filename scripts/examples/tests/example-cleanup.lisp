;;; Prove a tutorial failure keeps its original error and reaps its owned daemon.
;;;
;;;   sbcl --script scripts/test-processes/test-processes.lisp \
;;;       sbcl --script scripts/examples/tests/example-cleanup.lisp
;;;
;;; Runs the examples with a failure injected before the tutorial terminates its
;;; daemon. The run must fail with that error, report no secondary cleanup
;;; failure, and show one successful descendant-cleanup check from the group's
;;; supervisor. `mise run integration` runs this under its own supervisor.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../../support/support.lisp" *load-truename*)))

(defpackage #:libtmux.scripts.example-cleanup
  (:use #:cl #:libtmux.scripts))

(in-package #:libtmux.scripts.example-cleanup)

(defun occurrences (needle haystack)
  (loop with start = 0
        for found = (search needle haystack :start2 start)
        while found count t do (setf start (1+ found))))

(defun main ()
  (let ((root (directory-above *load-truename* 3)))
    (multiple-value-bind (code output error-output)
        (run (list "sbcl" "--script"
                   (uiop:native-namestring (merge-pathnames "scripts/examples/examples.lisp" root)))
             :environment (merge-environment "LIBTMUX_TEST_FAIL_TUTORIAL_BEFORE_TERMINATION" "1")
             :timeout 120 :check nil)
      (declare (ignore output))
      (when (eql 0 code)
        (fail "The injected tutorial failure unexpectedly succeeded"))
      (unless (search "Injected tutorial failure before termination" error-output)
        (fail "The tutorial runner replaced the injected failure"))
      (when (search "Cleanup also failed" error-output)
        (fail "The tutorial runner did not clean up after the injected failure"))
      (unless (= 1 (occurrences "Owned child exited 1; descendant cleanup: PASS" error-output))
        (fail "The tutorial failure lacks successful descendant-cleanup evidence"))
      (format t "Tutorial failure cleanup and original error retention: PASS~%")
      0)))

(main-when-script #'main)
