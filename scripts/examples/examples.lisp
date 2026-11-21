;;; Run the shipped Lisp examples and the tutorial against owned tmux daemons,
;;; including from an extracted source archive.
;;;
;;;   sbcl --script scripts/examples/examples.lisp [--source-root DIR]
;;;
;;; Two groups run as separate children, each under scripts/test-processes with
;;; its 60-second cap and descendant check: "core" (assertions, tutorial,
;;; quickstart, workspace command line, managed daemon, pane operations,
;;; decoded configuration, and control on tmux 3.8 or newer) and
;;; "owned-workspace" (the owned-document command line and its example). Each
;;; example starts and stops its own daemon through the library. The combined
;;; evidence goes to dist/examples-evidence.json. LIBTMUX_TEST_TMUX selects a
;;; native tmux binary; `mise run examples` and `mise run package-examples`
;;; run this script.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))
(unless (find-package "CL-PPCRE")
  (asdf:load-system "cl-ppcre"))
(unless (find-package "LIBTMUX")
  (asdf:load-system "libtmux"))

(defpackage #:libtmux.scripts.examples
  (:use #:cl #:libtmux.scripts)
  (:export #:tutorial-forms #:tutorial-script))

(in-package #:libtmux.scripts.examples)

(defparameter *tutorial-ending*
  '("(terminate-owned-server *socket-path*)" "(tm:stop-daemon *daemon*)" "(uiop:quit)"))

(defun trim (string) (string-trim '(#\Space #\Tab #\Newline #\Return) string))

(defun tutorial-forms (markdown)
  "Return the Lisp code blocks of MARKDOWN in reading order."
  (let ((forms '()))
    (cl-ppcre:do-register-groups (form) ("(?ms)^```lisp\\n(.*?)^```$" markdown)
      (push form forms))
    (nreverse forms)))

(defun tutorial-script (root forms &key (inject-failure nil))
  "Return the source of one program that runs every tutorial block in order."
  (let ((ending (last forms 3)))
    (unless (equal (mapcar #'trim ending) *tutorial-ending*)
      (fail "Tutorial must terminate its daemon, stop it and exit the REPL"))
    (format nil "(load ~S)
(setf sb-ext:*invoke-debugger-hook*
      (lambda (condition hook)
        (declare (ignore hook))
        (format *error-output* \"~~&~~A~~%\" condition)
        (let* ((package (find-package \"LIBTMUX.EXAMPLES\"))
               (symbol (and package (find-symbol \"*DAEMON*\" package))))
          (when (and symbol (boundp symbol))
            (ignore-errors (funcall (find-symbol \"STOP-DAEMON\" \"LIBTMUX\") (symbol-value symbol)))))
        (sb-ext:exit :code 1 :abort t)))
~{~A~^~%~}
(assert (equal '(2 3 4 4)
               (list (length (tm:sessions *snapshot*))
                     (length (tm:windows *snapshot*))
                     (length (tm:window-links *snapshot*))
                     (length (tm:panes *snapshot*)))))
(assert (find \"editor\" (tm:windows *snapshot*) :key #'tm:name :test #'string=))
(tm:with-client (client :socket-path *socket-path*)
  (assert (find \"api #{literal}\" (tm:fetch-windows client) :key #'tm:name :test #'string=)))
(format t \"TUTORIAL PASS: every Lisp block executed in reading order~~%\")
~A~{~A~^~%~}
(assert (not (probe-file (uiop:pathname-directory-pathname *socket-path*))))
(assert (zerop (length (tm:pending-daemon-cleanups))))
~A
"
            (uiop:native-namestring (merge-pathnames "tools/load.lisp" root))
            (butlast forms 3)
            (if inject-failure "(error \"Injected tutorial failure before termination\")" "")
            (subseq ending 0 2)
            (third ending))))

;;; Running examples

(defstruct (context (:conc-name context-) (:constructor build-context))
  root program version environment)

(defun run-lisp (context script &key arguments directory (timeout 60) extra-environment)
  "Run SCRIPT with sbcl --script, inheriting output; fail on any nonzero exit."
  (run (append (list "sbcl" "--script" (uiop:native-namestring script)) arguments)
       :directory directory :timeout timeout :output :inherit :error-output :inherit
       :environment (or extra-environment (context-environment context))))

(defun example (context name &key directory)
  (run-lisp context (merge-pathnames (format nil "examples/~A" name) (context-root context))
            :directory (or directory (uiop:temporary-directory))))

(defun workspace-cli (context directory arguments &key (expected 0) environment)
  "Run the workspace command line; return its parsed JSON from the right stream."
  (multiple-value-bind (code output error-output)
      (run (list* "sbcl" "--script"
                  (uiop:native-namestring (merge-pathnames "tools/workspace-cli.lisp" (context-root context)))
                  arguments)
           :directory directory :timeout 60 :check nil :input nil
           :environment (or environment (context-environment context)))
    (unless (eql code expected)
      (fail "Workspace CLI ~A: expected ~D, got ~D: ~A" (first arguments) expected code error-output))
    (let ((unused (if (eql expected 0) error-output output)))
      (unless (string= "" unused)
        (fail "Workspace CLI ~A wrote unexpected ~:[stdout~;stderr~]: ~A"
              (first arguments) (eql expected 0) unused)))
    (json-parse (if (eql expected 0) output error-output))))

(defun check (condition control &rest arguments)
  (unless condition (apply #'fail control arguments)))

(defun fixture-session (client)
  (let ((outcome (libtmux:new-session client :name "fixture" :width 120 :height 40
                                             :command '("/bin/cat"))))
    (when (libtmux:outcome-observation-error outcome)
      (error (libtmux:outcome-observation-error outcome)))))

(defmacro with-fixture-daemon ((context socket client) &body body)
  "Start an owned daemon with one fixture session; bind SOCKET and CLIENT."
  `(libtmux:with-daemon (daemon :program (context-program ,context))
     (let ((,socket (libtmux:daemon-socket-path daemon)))
       (libtmux:with-client (,client :program (libtmux:daemon-program daemon) :socket-path ,socket)
         (fixture-session ,client)
         ,@body))))

(defun declared-panes (client)
  "Return sorted 'INDEX NAME' strings, one per pane of the session named declared."
  (let* ((snapshot (libtmux:fetch-snapshot client))
         (session (find "declared" (libtmux:sessions snapshot) :key #'libtmux:name :test #'string=)))
    (sort (loop for link across (libtmux:window-links session)
                append (loop for nil across (libtmux:panes (libtmux:window link))
                             collect (format nil "~D ~A" (libtmux:index link)
                                             (libtmux:name (libtmux:window link)))))
          #'string<)))

(defun run-workspace-cli (context directory)
  "Exercise the shipped entry point on the workspace/1 document, then check live tmux."
  (with-fixture-daemon (context socket client)
    (let* ((document (uiop:native-namestring (merge-pathnames "examples/workspace.json" (context-root context))))
           (program (uiop:native-namestring (context-program context)))
           (responses
             (loop for arguments in (list (list "validate" document) (list "plan" document)
                                          (list "apply" document "--socket-path" socket "--program" program)
                                          (list "apply" document "--socket-path" socket "--program" program))
                   collect (workspace-cli context directory arguments))))
      (check (json-equal (first responses)
                         (obj "status" "valid" "schema" "libtmux.lisp.workspace/1" "session" "declared"
                              "windows" 2 "panes" 3))
             "Unexpected validate response")
      (check (and (equal "planned" (jref (second responses) "status"))
                  (eql 5 (jref (second responses) "steps")))
             "Unexpected plan response")
      (check (json-equal (third responses)
                         (obj "status" "applied" "session" "declared" "created" :true "outcomes" 5
                              "windows" 2 "panes" 3))
             "Unexpected first apply response")
      (check (json-equal (fourth responses)
                         (obj "status" "applied" "session" "declared" "created" :false "outcomes" 0
                              "windows" 2 "panes" 3))
             "Unexpected repeated apply response")
      (check (equal '("2 code" "2 code" "5 shell") (declared-panes client)) "Unexpected live topology")
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (session (find "declared" (libtmux:sessions snapshot) :key #'libtmux:name :test #'string=))
             (entries (libtmux:show-environment client :scope :session :target session
                                                       :names (vector "APP_LABEL"))))
        (check (equal "declared" (getf (aref entries 0) :value)) "Unexpected session environment"))
      (obj "entrypoint" "tools/workspace-cli.lisp" "responses" (coerce responses 'vector)
           "live_topology" "PASS" "session_environment" "PASS"))))

(defun run-owned-workspace-cli (context directory)
  "Check the entry point's complete owned-document workflow."
  (with-fixture-daemon (context socket client)
    (let* ((program (uiop:native-namestring (context-program context)))
           (environment (environment-with
                         (context-environment context)
                         "ASDF_OUTPUT_TRANSLATIONS"
                         (format nil "(:output-translations (t ~S) :ignore-inherited-configuration)"
                                 (uiop:native-namestring (merge-pathnames "owned-cli-fasl/" directory)))))
           (document (merge-pathnames "examples/owned-workspace.json" (context-root context)))
           (summaries '()))
      (flet ((invoke (command &key (path document) reconcile (expected 0))
               (let* ((arguments (append (list command (uiop:native-namestring path))
                                         (unless (string= command "validate")
                                           (list "--socket-path" socket "--program" program))
                                         (when reconcile (list "--reconcile"))))
                      (data (workspace-cli context directory arguments :expected expected
                                                                        :environment environment)))
                 (push (obj "command" command "reconcile" (if reconcile :true :false)
                            "exit_code" expected "status" (jref data "status"))
                       summaries)
                 data)))
        (let ((validated (invoke "validate")))
          (check (and (equal "libtmux.lisp.workspace/2" (jref validated "schema"))
                      (equal "demo-workspace" (jref validated "id"))
                      (eql 2 (jref validated "windows")) (eql 3 (jref validated "panes")))
                 "Unexpected owned validate response")
          (check (eq :true (jref (invoke "plan") "data" "publish-p")) "The first plan must publish")
          (let* ((first (jref (invoke "apply") "data"))
                 (original (jref first "record")))
            (check (and (equal "published" (jref first "status"))
                        (equal "succeeded" (jref first "publication-status")))
                   "The first apply must publish")
            (let ((again (jref (invoke "apply") "data")))
              (check (and (equal "unchanged" (jref again "status"))
                          (eq :null (jref again "publication-status"))
                          (eq :false (jref again "plan" "publish-p"))
                          (equal (jref original "revision") (jref again "record" "revision")))
                     "The second apply must be a no-op"))
            (let* ((changed (json-read-file document))
                   (window (jref changed "session" "windows" 0))
                   (path (merge-pathnames "owned-cli.json" directory)))
              (jset (jref changed "session") "name" "owned-cli-renamed")
              (jset window "name" "editors")
              (jset window "layout" "even-vertical")
              (jset window "panes" (concatenate 'vector (jref window "panes")
                                                (vector (obj "id" "extra" "command" (vector "/bin/cat")))))
              (json-write-file path changed)
              (let ((refusal (invoke "plan" :path path :expected 1)))
                (check (and (equal "workspace-conflict" (jref refusal "condition"))
                            (plusp (length (jref refusal "plan" "changes"))))
                       "An edited plan without reconcile must be refused"))
              (check (eq :true (jref (invoke "plan" :path path :reconcile t) "data" "publish-p"))
                     "A reconciling plan must publish")
              (let ((after (jref (invoke "apply" :path path :reconcile t) "data" "record")))
                (check (and (equal (jref original "session" "physical-id") (jref after "session" "physical-id"))
                            (equal (jref original "windows" 0 "physical-id") (jref after "windows" 0 "physical-id"))
                            (equal (jref original "windows" 0 "panes" 0 "physical-id")
                                   (jref after "windows" 0 "panes" 0 "physical-id"))
                            (= 3 (length (jref after "windows" 0 "panes"))))
                       "Reconcile must keep physical identities")
                (let ((inspection (jref (invoke "inspect") "data")))
                  (check (and (eq :true (jref inspection "complete-p"))
                              (equal "idle" (jref inspection "status")))
                         "Inspection after publication must be idle"))
                (jset window "layout" (obj "custom" "0000,80x24,0,0,0"))
                (json-write-file path changed)
                (let ((failed (invoke "apply" :path path :reconcile t :expected 1)))
                  (check (and (equal "workspace-apply-failed" (jref failed "condition"))
                              (equal "select-layout" (jref failed "failedStep" "action"))
                              (plusp (length (jref failed "outcomes")))
                              (plusp (length (jref failed "causes")))
                              (eq :null (jref failed "data" "publication-status"))
                              (equal (jref after "revision") (jref failed "data" "record" "revision")))
                         "A failed apply must keep its evidence and leave the record unpublished"))
                (let ((incomplete (jref (invoke "inspect" :path path) "data")))
                  (check (and (eq :true (jref incomplete "complete-p"))
                              (equal "busy" (jref incomplete "status")))
                         "Inspection after a failed apply must be busy")))))
          (obj "entrypoint" "tools/workspace-cli.lisp" "schema" (jref validated "schema")
               "cold_validation" "PASS" "operations" (coerce (reverse summaries) 'vector)
               "stable_ids" "PASS" "failed_apply_and_inspection" "PASS"))))))

(defun run-tutorial (context)
  (let* ((root (context-root context))
         (forms (tutorial-forms (read-text (merge-pathnames "docs/tutorial.md" root)))))
    (with-temporary-directory (directory "libtmux-lisp-tutorial")
      (let ((script (write-text (merge-pathnames "tutorial.lisp" directory)
                                (tutorial-script
                                 root forms
                                 :inject-failure (uiop:getenv "LIBTMUX_TEST_FAIL_TUTORIAL_BEFORE_TERMINATION")))))
        (run-lisp context script :directory root)))
    (length forms)))

(defun control-example-p (context)
  "True when the selected tmux is 3.8 or newer, the control mode floor."
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings "^tmux ([0-9]+)\\.([0-9]+)" (context-version context))
    (and match
         (let ((major (parse-integer (aref groups 0))) (minor (parse-integer (aref groups 1))))
           (or (> major 3) (and (= major 3) (>= minor 8)))))))

(defun source-hashes (root)
  (cons :object
        (loop for path in (append (sort (directory (merge-pathnames "examples/*.*" root)
                                                   :resolve-symlinks nil)
                                        #'string< :key #'namestring)
                                  (mapcar (lambda (name) (merge-pathnames name root))
                                          '("README.md" "docs/tutorial.md" "docs/workspace-owned.md"
                                            "scripts/examples/examples.lisp"
                                            "scripts/test-processes/test-processes.lisp"
                                            "tools/workspace-cli.lisp")))
              when (probe-file path)
                collect (cons (enough-namestring path root) (sha256-file path)))))

(defun run-group (context group)
  "Run one group of examples and return its evidence."
  (let ((started (monotonic-seconds))
        (core (string= group "core"))
        (evidence '()))
    (flet ((put (key value) (setf evidence (append evidence (list (cons key value))))))
      (if core
          (progn
            (example context "run.lisp")
            (put "tutorial_lisp_blocks" (run-tutorial context))
            (example context "quickstart.lisp")
            (with-temporary-directory (directory "libtmux-lisp-example")
              (put "workspace_cli" (run-workspace-cli context directory)))
            (example context "managed-daemon.lisp")
            (example context "drive-panes.lisp")
            (example context "configuration.lisp")
            (example context "capabilities.lisp")
            (if (control-example-p context)
                (progn (example context "control.lisp" :directory (context-root context))
                       (put "persistent_control" "PASS"))
                (put "persistent_control" "SKIP: requires tmux 3.8 or newer")))
          (progn
            (with-temporary-directory (directory "libtmux-lisp-owned-cli")
              (put "owned_workspace_cli" (run-owned-workspace-cli context directory)))
            (example context "owned-workspace.lisp")
            (put "owned_workspace_program" "PASS"))))
    (assert (zerop (length (libtmux:pending-daemon-cleanups))))
    (append (list (cons "status" "PASS") (cons "group" group)
                  (cons "tmux" (context-version context))
                  (cons "tmux_program_sha256" (sha256-file (context-program context)))
                  (cons "sbcl" (format nil "SBCL ~A" (lisp-implementation-version)))
                  (cons "elapsed_seconds" (/ (round (* 1000 (- (monotonic-seconds) started))) 1000d0))
                  (cons "source_sha256" (source-hashes (context-root context)))
                  (cons "daemon_cleanup" "PASS")
                  (cons "optional_libraries_loaded" (if core (vector "cl-ppcre" "com.inuoe.jzon")
                                                        (vector "com.inuoe.jzon")))
                  (cons "optional_systems_loaded" (if core (vector "libtmux/regex" "libtmux/json" "libtmux/workspace")
                                                      (vector "libtmux/workspace"))))
            (if core
                (append (list (cons "tutorial_daemon_cleanup" "PASS"))
                        (loop for key in '("tutorial_lisp_blocks" "workspace_cli" "persistent_control")
                              collect (assoc key evidence :test #'string=))
                        (list (cons "managed_daemon" "PASS") (cons "pane_operations" "PASS")
                              (cons "decoded_configuration" "PASS")))
                evidence))))

(defun make-context (root bin)
  "Build the run context. The examples start the library's default `tmux`, so BIN
gets a `tmux` link to the selected binary and leads their PATH."
  (let* ((program (or (find-program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux"))
                      (fail "Install tmux or set LIBTMUX_TEST_TMUX to a native binary")))
         (environment (progn
                        (sb-posix:symlink (uiop:native-namestring program)
                                          (uiop:native-namestring (merge-pathnames "tmux" bin)))
                        (merge-environment "TMUX" nil "TMUX_PANE" nil "LC_ALL" "C.UTF-8"
                                           "PATH" (format nil "~A:~A"
                                                          (string-right-trim "/" (uiop:native-namestring bin))
                                                          (or (uiop:getenv "PATH") ""))))))
    (build-context :root root :program (uiop:native-namestring program) :environment environment
                  :version (string-trim '(#\Newline)
                                        (nth-value 1 (run (list (uiop:native-namestring program) "-V")
                                                          :environment environment))))))

(defun orchestrate (root)
  "Run both groups as supervised children and write the combined evidence."
  (let* ((started (monotonic-seconds))
         (output (merge-pathnames "dist/" root))
         (combined (merge-pathnames "examples-evidence.json" output))
         (expected (source-hashes root))
         (records '()))
    (ensure-directories-exist output)
    (when (probe-file combined) (delete-file combined))
    (with-temporary-directory (directory "libtmux-lisp-example-evidence")
      (dolist (group '("core" "owned-workspace"))
        (let ((path (merge-pathnames (format nil "~A.json" group) directory)))
          (run (list "sbcl" "--script"
                     (uiop:native-namestring (merge-pathnames "scripts/test-processes/test-processes.lisp" root))
                     "sbcl" "--script"
                     (uiop:native-namestring (merge-pathnames "scripts/examples/examples.lisp" root))
                     "--source-root" (uiop:native-namestring root) "--group" group
                     "--evidence" (uiop:native-namestring path))
               :output :inherit :error-output :inherit :timeout 120)
          (let ((record (json-read-file path)))
            (check (and (equal "PASS" (jref record "status")) (equal "PASS" (jref record "daemon_cleanup"))
                        (equal group (jref record "group")) (json-equal expected (jref record "source_sha256")))
                   "Group ~A reported failed cleanup or changed sources" group)
            (push (cons group record) records)))))
    (check (json-equal expected (source-hashes root)) "Example sources changed during the run")
    (let* ((core (cdr (assoc "core" records :test #'string=)))
           (owned (cdr (assoc "owned-workspace" records :test #'string=))))
      (check (every (lambda (key) (equal (jref core key) (jref owned key)))
                    '("tmux" "tmux_program_sha256" "sbcl"))
             "The groups ran on different runtimes")
      (let ((evidence (cons :object (remove "group" (copy-alist (cdr core)) :key #'car :test #'string=))))
        (dolist (key '("owned_workspace_cli" "owned_workspace_program"))
          (jset evidence key (jref owned key)))
        (jset evidence "elapsed_seconds" (/ (round (* 1000 (- (monotonic-seconds) started))) 1000d0))
        (jset evidence "groups"
              (cons :object (loop for (group . record) in (reverse records)
                                  collect (cons group (obj "status" (jref record "status")
                                                           "elapsed_seconds" (jref record "elapsed_seconds"))))))
        (json-write-file combined evidence)
        (format t "~A~%" (json-string evidence :indent nil))))))

(defun main ()
  (let* ((arguments (rest sb-ext:*posix-argv*))
         (root (uiop:ensure-directory-pathname
                (truename (or (second (member "--source-root" arguments :test #'string=))
                              (directory-above *load-truename* 2)))))
         (group (second (member "--group" arguments :test #'string=)))
         (evidence (second (member "--evidence" arguments :test #'string=))))
    (cond ((null group) (orchestrate root) 0)
          ((member group '("core" "owned-workspace") :test #'string=)
           (with-temporary-directory (bin "libtmux-lisp-tmux")
             (let* ((record (cons :object (run-group (make-context root bin) group)))
                    (path (or (and evidence (merge-pathnames evidence (uiop:getcwd)))
                              (merge-pathnames (format nil "dist/examples-evidence-~A.json" group) root))))
               (json-write-file path record)
               (format t "~A~%" (json-string record :indent nil))
               0)))
          (t (fail "Unknown group ~A" group)))))

(main-when-script #'main)
