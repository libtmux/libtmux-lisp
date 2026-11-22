(require :sb-posix)
(dolist (name '("TMUX" "TMUX_PANE" "LIBTMUX_SOCKET" "LIBTMUX_SOCKET_PATH"))
  (sb-posix:unsetenv name))
(let ((tmux (sb-ext:posix-getenv "LIBTMUX_TEST_TMUX")))
  (when (and tmux
             (every (lambda (char)
                      (member char '(#\Space #\Tab #\Newline #\Return #\Vt #\Page)))
                    tmux))
    (sb-posix:unsetenv "LIBTMUX_TEST_TMUX")))

(load (merge-pathnames "load.lisp" *load-truename*))
(let* ((arguments (uiop:command-line-arguments))
       (suites (mapcar
                (lambda (argument)
                  (or (cdr (assoc argument '(("unit" . :unit) ("query" . :query)
                                            ("regex" . :regex) ("json" . :json) ("scripts" . :scripts)
                                            ("control" . :control)
                                            ("transport-integration" . :transport-integration)
                                            ("workspace-integration" . :workspace-integration)
                                            ("workspace-inspection-integration" . :workspace-inspection-integration)
                                            ("workspace-writer-integration" . :workspace-writer-integration)
                                            ("workspace-apply-integration" . :workspace-apply-integration)
                                            ("workspace-publication-integration" . :workspace-publication-integration)
                                            ("workspace-apply-race-integration" . :workspace-apply-race-integration)
                                            ("workspace-public-integration" . :workspace-public-integration)
                                            ("control-integration" . :control-integration)
                                            ("configuration-integration" . :configuration-integration)
                                            ("workspace" . :workspace)
                                            ("integration" . :integration)) :test #'string=))
                      (error "Unknown test suite: ~A" argument)))
                arguments)))
  (unless suites
    (error "Expected unit, query, regex, json, scripts, control, transport-integration, control-integration, configuration-integration, workspace-integration, workspace-inspection-integration, workspace-writer-integration, workspace-apply-integration, workspace-publication-integration, workspace-apply-race-integration, workspace-public-integration, workspace or integration"))
  (dolist (suite suites)
    (asdf:load-system (ecase suite
                        (:unit "libtmux/tests")
                        (:query "libtmux/tests/query")
                        (:regex "libtmux/tests/regex")
                        (:json "libtmux/tests/json")
                        (:scripts "libtmux/tests/scripts")
                        (:control "libtmux/tests/control")
                        (:workspace "libtmux/tests/workspace")
                        ((:transport-integration :integration :control-integration
                          :configuration-integration :workspace-integration :workspace-inspection-integration
                          :workspace-writer-integration :workspace-apply-integration
                          :workspace-publication-integration :workspace-apply-race-integration
                          :workspace-public-integration) "libtmux/tests/integration")))
    (format t "~&SBCL ~A; ASDF ~A; UIOP ~A~%"
            (lisp-implementation-version) (asdf:asdf-version)
            (asdf:component-version (asdf:find-system "uiop")))
    (when (eq suite :integration)
      (write-string (uiop:run-program
                     (list (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux") "-V")
                     :force-shell nil :output :string)))
    (unless (uiop:symbol-call :libtmux.tests :run-suite suite) (uiop:quit 1)))
  (uiop:quit 0))
