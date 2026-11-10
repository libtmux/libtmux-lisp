(in-package #:libtmux.tests)

(in-suite workspace-integration)

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

(test workspace-apply-handles-zero-index-reservations-and-ordered-large-layouts
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((zero
               (libtmux.workspace:make-workspace
                '(:schema "libtmux.lisp.workspace/1"
                  :session (:name "zero-first"
                            :windows
                            #((:name "main" :index 0
                               :panes #((:command #("/bin/cat")))))))))
             (reserved
               (libtmux.workspace:make-workspace
                '(:schema "libtmux.lisp.workspace/1"
                  :session (:name "reserved-zero"
                            :windows
                            #((:name "floating"
                               :panes #((:command #("/bin/cat"))))
                              (:name "zero" :index 0
                               :panes #((:command #("/bin/cat")))))))))
             (directory (fixture-directory fixture))
             (paths (loop for name in '("a" "b" "c" "d" "e" "f")
                          for path = (merge-pathnames (format nil "pane-~A/" name)
                                                      directory)
                          do (ensure-directories-exist path)
                          collect (string-right-trim "/" (namestring path))))
             (large
               (libtmux.workspace:make-workspace
                `(:schema "libtmux.lisp.workspace/1"
                  :session (:name "large-layout"
                            :windows
                            #((:name "six" :layout :main-vertical
                               :panes ,(map 'vector
                                            (lambda (path)
                                              (list :cwd path
                                                    :command #("/bin/cat")))
                                            paths))))))))
        (libtmux.workspace:apply-workspace client zero)
        (libtmux.workspace:apply-workspace client reserved)
        (fixture-ok fixture "set-option" "-g" "default-size" "80x9")
        (let* ((result (libtmux.workspace:apply-workspace client large))
               (snapshot (libtmux.workspace:result-snapshot result))
               (zero-session (find "zero-first" (libtmux:sessions snapshot)
                                   :key #'libtmux:name :test #'string=))
               (reserved-session (find "reserved-zero" (libtmux:sessions snapshot)
                                       :key #'libtmux:name :test #'string=))
               (large-session (find "large-layout" (libtmux:sessions snapshot)
                                    :key #'libtmux:name :test #'string=))
               (large-window (libtmux:window
                              (aref (libtmux:window-links large-session) 0))))
          (is (= 0 (libtmux:index (aref (libtmux:window-links zero-session) 0))))
          (is (= 0 (libtmux:index
                    (find "zero" (libtmux:window-links reserved-session)
                          :key (lambda (link) (libtmux:name (libtmux:window link)))
                          :test #'string=))))
          (is (= 6 (length (libtmux:panes large-window))))
          (is (equal paths (map 'list #'libtmux:current-path
                                (libtmux:panes large-window)))))))))

(test workspace-explicit-shell-environment-and-custom-layout
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((directory (namestring (fixture-directory fixture)))
             (script (concatenate 'string directory "record.py"))
             (program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux"))
             (value "λ$; literal")
             (layout (libtmux:field-value
                      (aref (libtmux:windows (libtmux:fetch-snapshot client)) 0)
                      :window/layout)))
        (with-open-file (stream script :direction :output :if-exists :error)
          (write-string "import os, subprocess, sys
with open(os.path.join(os.environ['WS_DIRECTORY'], sys.argv[1]), 'w') as stream:
    stream.write(os.environ['WS_VALUE'] + '\\n' + sys.argv[2])
subprocess.run([os.environ['WS_PROGRAM'], '-N', '-S', os.environ['WS_SOCKET'], 'wait-for', '-S', 'workspace-' + sys.argv[1]], check=True)
sys.stdin.buffer.read()
" stream))
        (let* ((workspace
                 (libtmux.workspace:make-workspace
                  `(:schema "libtmux.lisp.workspace/1"
                    :session
                    (:name "creation-inputs"
                     :environment ,(vector (cons "WS_VALUE" value)
                                           (cons "WS_SCRIPT" script)
                                           (cons "WS_DIRECTORY" directory)
                                           (cons "WS_PROGRAM" program)
                                           (cons "WS_SOCKET" (fixture-socket fixture)))
                     :windows
                     #((:name "first"
                        :panes #((:shell-command "exec /usr/bin/python3 \"$WS_SCRIPT\" first \"$WS_VALUE\"")
                                 (:command ,(vector "/usr/bin/python3" script "split" "$WS_VALUE"))))
                       (:name "second" :layout (:custom ,layout)
                        :panes #((:shell-command "exec /usr/bin/python3 \"$WS_SCRIPT\" window \"$WS_VALUE\""))))))))
               (result (libtmux.workspace:apply-workspace client workspace)))
          (is (every (lambda (outcome) (eq :succeeded (libtmux:outcome-status outcome)))
                     (libtmux.workspace:result-outcomes result)))
          (dolist (name '("first" "split" "window"))
            (libtmux:run-command client (list "wait-for" (concatenate 'string "workspace-" name))
                                       :effect :read :timeout 0.5)
            (is (string= (format nil "~A~%~A" value
                                 (if (string= name "split") "$WS_VALUE" value))
                         (uiop:read-file-string (concatenate 'string directory name)))))
          (let ((libtmux.workspace::*execute-step-function*
                  (lambda (&rest arguments)
                    (declare (ignore arguments))
                    (error "Topology reuse dispatched a mutation"))))
            (is (zerop (length (libtmux.workspace:result-outcomes
                               (libtmux.workspace:apply-workspace client workspace)))))))
        (handler-case
            (progn
              (libtmux.workspace:apply-workspace
               client (libtmux.workspace:make-workspace
                       '(:schema "libtmux.lisp.workspace/1"
                         :session (:name "bad-custom"
                                   :windows #((:name "main" :layout (:custom "0000,80x24,0,0,0")
                                               :panes #((:command #("/bin/cat")))))))))
              (fail "Tmux accepted a custom layout with an incorrect checksum"))
          (libtmux.workspace:workspace-apply-failed (condition)
            (let ((outcomes (libtmux.workspace:result-outcomes condition)))
              (is (= 2 (length outcomes)))
              (is (eq :succeeded (libtmux:outcome-status (aref outcomes 0))))
              (is (not (eq :succeeded (libtmux:outcome-status (aref outcomes 1)))))
              (is (zerop (nth-value 2 (fixture-command fixture "-N" "has-session" "-t" "=fixture"))))
              (is (eq :select-layout
                      (libtmux.workspace:step-action
                       (libtmux.workspace:failed-step condition)))))))))))
