(require :asdf)
(asdf:load-asd (merge-pathnames "../libtmux.asd" *load-truename*))
(let* ((arguments (uiop:command-line-arguments))
       (suite (cond ((equal (first arguments) "unit") :unit)
                    ((equal (first arguments) "query") :query)
                    ((equal (first arguments) "integration") :integration)
                    (t (error "Expected unit, query or integration")))))
  (asdf:load-system (ecase suite
                      (:unit "libtmux/tests")
                      (:query "libtmux/tests/query")
                      (:integration "libtmux/tests/integration")))
  (format t "~&SBCL ~A; ASDF ~A; UIOP ~A~%"
          (lisp-implementation-version) (asdf:asdf-version)
          (asdf:component-version (asdf:find-system "uiop")))
  (when (eq suite :integration)
    (write-string (uiop:run-program
                   (list (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux") "-V")
                   :force-shell nil :output :string)))
  (uiop:quit (if (uiop:symbol-call :libtmux.tests :run-suite suite) 0 1)))
