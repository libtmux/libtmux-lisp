(in-package #:libtmux.tests)

(in-suite integration)

(defun call-workspace-cli-for-integration (arguments)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (values (uiop:symbol-call :libtmux.workspace.cli :main :arguments arguments
                              :stdout stdout :stderr stderr)
            (get-output-stream-string stdout)
            (get-output-stream-string stderr))))

(defun live-workspace-data (directory child)
  (list :schema "libtmux.lisp.workspace/1"
        :session
        (list :name "workspace-live"
              :cwd directory
              :windows
              (vector
               (list :name "editor" :index 1 :layout :tiled
                     :panes
                     (vector (list :command (vector "/bin/cat"))
                             (list :cwd child
                                   :command (vector "/bin/cat"))))
               (list :name "shell" :index 4
                     :panes (vector (list :command (vector "/bin/cat"))))))))

(test workspace-apply-creates-and-then-reuses-an-exact-live-topology
  (with-tmux-fixture (fixture)
    (let* ((directory (string-right-trim "/" (namestring (fixture-directory fixture))))
           (child-directory (merge-pathnames "child/" (fixture-directory fixture))))
      (ensure-directories-exist child-directory)
      (let* ((child (string-right-trim "/" (namestring child-directory)))
             (workspace
               (libtmux.workspace:make-workspace
                (live-workspace-data directory child))))
        (with-fixture-client (client fixture)
          (let* ((result (libtmux.workspace:apply-workspace client workspace))
                 (snapshot (libtmux.workspace:result-snapshot result))
                 (session (find "workspace-live" (libtmux:sessions snapshot)
                                :key #'libtmux:name :test #'string=))
                 (links (libtmux:window-links session))
                 (editor-link (find "editor" links
                                    :key (lambda (link)
                                           (libtmux:name (libtmux:window link)))
                                    :test #'string=))
                 (shell-link (find "shell" links
                                   :key (lambda (link)
                                          (libtmux:name (libtmux:window link)))
                                   :test #'string=))
                 (editor (libtmux:window editor-link)))
            (is (libtmux.workspace:result-created-p result))
            (is (= 5 (length (libtmux.workspace:result-outcomes result))))
            (let ((outcomes (libtmux.workspace:result-outcomes result)))
              (is (every (lambda (outcome)
                           (eq :succeeded (libtmux:outcome-status outcome)))
                         outcomes))
              (setf (aref outcomes 0) nil)
              (is (typep (aref (libtmux.workspace:result-outcomes result) 0)
                         'libtmux:command-outcome)))
            (is (= 1 (libtmux:index editor-link)))
            (is (= 4 (libtmux:index shell-link)))
            (is (= 2 (length (libtmux:panes editor))))
            (is (= 1 (length (libtmux:panes (libtmux:window shell-link)))))
            (is (equal (list directory child)
                       (map 'list #'libtmux:current-path
                            (libtmux:panes editor))))
            (is (plusp (length (libtmux:field-value editor :window/layout))))
            (let ((libtmux.workspace::*execute-step-function*
                    (lambda (&rest arguments)
                      (declare (ignore arguments))
                      (error "A proven no-op executed a mutation"))))
              (let ((again (libtmux.workspace:apply-workspace client workspace)))
                (is (not (libtmux.workspace:result-created-p again)))
                (is (zerop (length (libtmux.workspace:result-outcomes again))))))))))))

(test workspace-conflict-fetches-but-dispatches-no-mutation
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((workspace
               (libtmux.workspace:make-workspace
                '(:schema "libtmux.lisp.workspace/1"
                  :session (:name "fixture"
                            :windows #((:name "different" :panes #(())))))))
             (libtmux.workspace::*execute-step-function*
               (lambda (&rest arguments)
                 (declare (ignore arguments))
                 (error "A conflicting workspace dispatched a mutation"))))
        (signals libtmux.workspace:workspace-conflict
          (libtmux.workspace:apply-workspace client workspace))))))

(test workspace-cli-applies-only-to-the-explicit-owned-endpoint
  (with-tmux-fixture (fixture)
    (let ((path (merge-pathnames "cli-workspace.json" (fixture-directory fixture))))
      (with-open-file (stream path :direction :output :if-exists :error
                                  :external-format :utf-8)
        (write-string
         "{\"schema\":\"libtmux.lisp.workspace/1\",\"session\":{\"name\":\"cli-live\",\"windows\":[{\"name\":\"main\",\"panes\":[{\"command\":[\"/bin/cat\"]}]}]}}"
         stream))
      (let ((program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")))
        (multiple-value-bind (code stdout stderr)
            (call-workspace-cli-for-integration
             (list "apply" (namestring path)
                   "--socket-path" (fixture-socket fixture)
                   "--program" program))
          (is (zerop code))
          (is (search "\"status\":\"applied\"" stdout))
          (is (search "\"created\":true" stdout))
          (is (string= "" stderr)))
        (multiple-value-bind (code stdout stderr)
            (call-workspace-cli-for-integration
             (list "apply" (namestring path)
                   "--socket-path" (fixture-socket fixture)
                   "--program" program))
          (is (zerop code))
          (is (search "\"created\":false" stdout))
          (is (string= "" stderr)))))))
