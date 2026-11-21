;;; Build the source archive and load it as an isolated consumer, without the
;;; project environment or optional libraries.
;;;
;;;   sbcl --script scripts/package/package.lisp [--examples]
;;;
;;; Writes dist/libtmux-source.tar.gz (entries under libtmux/, fixed owner and
;;; times from SOURCE_DATE_EPOCH or the HEAD commit) and dist/package-evidence.json.
;;; Each consumer check starts a fresh SBCL on the extracted tree: the core
;;; system must load without the query, workspace, regex, JSON or threading
;;; libraries; each optional system loads only its own dependencies; the
;;; workspace command line validates the shipped document. With --examples the
;;; integration suites, the documentation excerpts and the examples then run
;;; from the extracted tree. `mise run package` and `mise run package-examples`
;;; run this script.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))

(defpackage #:libtmux.scripts.package
  (:use #:cl #:libtmux.scripts)
  (:export #:source-files #:consumer-checks))

(in-package #:libtmux.scripts.package)

(defparameter *root-files*
  '("libtmux.asd" "LICENSE" "README.md" "CHANGELOG.md" "capabilities.json" "qlfile" "qlfile.lock" "mise.toml"
    ".tool-versions" "AGENTS.md" "verification.md"))

(defparameter *system-readmes*
  '("query/README.md" "regex/README.md" "json/README.md" "control/README.md"
    "workspace/README.md" "workspace/cli/README.md"))

(defparameter *trees*
  '("src/**/*.lisp" "tests/**/*.lisp" "docs/**/*.md" "data/*.json" "docs/assets/**/*.*"
    "examples/*.*" "tools/*.*" "scripts/**/*.*" ".github/**/*.*"))

(defun source-files (root)
  "Return the sorted relative names of the files the source archive holds."
  (sort (remove-duplicates
         (append (remove-if-not (lambda (name) (probe-file (merge-pathnames name root)))
                                (append *root-files* *system-readmes*))
                 (loop for pattern in *trees*
                       append (mapcar (lambda (path) (enough-namestring path root))
                                      (remove-if #'uiop:directory-pathname-p
                                                 (directory (merge-pathnames pattern root)
                                                            :resolve-symlinks nil)))))
         :test #'string=)
        #'string<))

(defun build-archive (root archive)
  "Write the deterministic source archive at ARCHIVE; return its SHA-256."
  (let ((epoch (or (uiop:getenv "SOURCE_DATE_EPOCH") (git root "show" "-s" "--format=%ct" "HEAD"))))
    (with-temporary-directory (directory "libtmux-lisp-package")
      (let ((list (write-text (merge-pathnames "files" directory)
                              (format nil "~{~A~%~}" (source-files root))))
            (tarball (merge-pathnames "source.tar" directory)))
        (run (list "tar" "--create" (format nil "--file=~A" (uiop:native-namestring tarball))
                   "--directory" (uiop:native-namestring root)
                   (format nil "--files-from=~A" (uiop:native-namestring list))
                   "--transform" "s,^,libtmux/," (format nil "--mtime=@~A" epoch)
                   "--owner=0" "--group=0" "--numeric-owner" "--sort=name"))
        (run (list "gzip" "-n" "-9" "-c" (uiop:native-namestring tarball)) :output archive)))
    (sha256-file archive)))

;;; Consumer checks

(defparameter *absent-optional-libraries*
  '("(assert (not (find-package :cl-ppcre)))" "(assert (not (find-package :com.inuoe.jzon)))"
    "(assert (not (find-package :bt2)))"))

(defun consumer-checks (extracted)
  "Return (NAME QLOT-P FORMS) for each isolated consumer of the tree at EXTRACTED."
  (let ((workspace-document (uiop:native-namestring (merge-pathnames "examples/workspace.json" extracted)))
        (archive-asd (uiop:native-namestring (merge-pathnames "libtmux.asd" extracted))))
  (list
   (list "core_consumer" nil
         (append '("(asdf:load-system \"libtmux\")" "(assert (find-package :libtmux))"
                   "(assert (not (find-package :libtmux.query)))"
                   "(assert (not (find-package :libtmux.workspace)))")
                 *absent-optional-libraries*
                 '("(assert (not (fboundp (find-symbol \"FEED-CONTROL-LINES\" :libtmux.internal))))")))
   (list "control_codec_consumer" nil
         (append '("(asdf:load-system \"libtmux/control\")"
                   "(let ((decoder (libtmux.internal::make-control-line-decoder))) (assert (equalp #() (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #(65 255))))) (assert (equalp #(#(65 255)) (libtmux.internal::feed-control-lines decoder (libtmux.internal::octet-vector #(10))))) (libtmux.internal::finish-control-lines decoder))"
                   "(assert (find-class (find-symbol \"CONNECTION\" :libtmux.control) nil))"
                   "(assert (equalp #(0 255) (libtmux.internal::decode-control-output-line (libtmux.internal::octet-vector #(37 111 117 116 112 117 116 32 37 49 32 92 48 48 48 255)))))")
                 *absent-optional-libraries*))
   (list "query_consumer" nil
         (append '("(asdf:load-system \"libtmux/query\")" "(assert (find-package :libtmux.query))"
                   "(handler-case (progn (libtmux.query:compile-filter :pane (quote (:regex-search :pane/current-command (:cl-ppcre \"nvim\")))) (error \"Regex compiled without libtmux/regex\")) (libtmux.query:invalid-filter ()))")
                 *absent-optional-libraries*))
   (list "regex_consumer" t
         (list "(setf *compile-verbose* nil *load-verbose* nil)"
           (format nil "(assert (equal (truename ~S) (truename (asdf:system-source-file \"libtmux/regex\"))))"
                   archive-asd)
           "(asdf:load-system \"libtmux/regex\")" "(assert (find-package :libtmux.regex))"
           "(assert (typep (libtmux.query:compile-filter :pane (quote (:regex-search :pane/current-command (:cl-ppcre \"^n\")))) (quote libtmux.query:compiled-filter)))"))
   (list "json_consumer" t
         '("(setf *compile-verbose* nil *load-verbose* nil)"
           "(asdf:load-system \"libtmux/json\")" "(assert (not (find-package :cl-ppcre)))"
           "(let* ((filter (libtmux.query:compile-filter :pane (quote (:and)))) (document (libtmux.json:write-filter filter))) (assert (typep (libtmux.json:read-filter document) (quote libtmux.query:compiled-filter))))"))
   (list "workspace_consumer" t
         (list "(setf *compile-verbose* nil *load-verbose* nil)"
               "(asdf:load-system \"libtmux/workspace/cli\")"
               (format nil "(let* ((workspace (libtmux.workspace:read-workspace ~S)) (plan (libtmux.workspace:plan-workspace workspace))) (assert (= 5 (length (libtmux.workspace:plan-steps plan)))))"
                       workspace-document)
               "(let* ((revision (make-string 32 :initial-element #\\A)) (record (libtmux.workspace::make-owned-record :pending (list :schema \"libtmux.lisp.workspace.pending/1\" :workspace \"archive\" :base \"0\" :writer revision :declaration (list :schema \"libtmux.lisp.workspace/2\" :id \"archive\" :session (list :id \"main\" :name \"archive\" :windows (vector (list :id \"shell\" :name \"shell\" :panes (vector (list :id \"shell\" :command #(\"/bin/cat\"))))))))))) (multiple-value-bind (descriptor chunks) (libtmux.workspace::encode-owned-record record) (assert (string= (libtmux.workspace::owned-record-json record) (libtmux.workspace::owned-record-json (libtmux.workspace::decode-owned-record \"archive\" :pending revision descriptor chunks))))))"
               (format nil "(let ((stdout (make-string-output-stream)) (stderr (make-string-output-stream))) (assert (zerop (libtmux.workspace.cli:main :arguments (list \"validate\" ~S) :stdout stdout :stderr stderr))) (assert (search \"\\\"status\\\":\\\"valid\\\"\" (get-output-stream-string stdout))) (assert (string= \"\" (get-output-stream-string stderr))))"
                       workspace-document))))))

(defun run-consumer (extracted environment forms)
  (run (append (list "sbcl" "--noinform" "--no-sysinit" "--no-userinit" "--non-interactive"
                     "--load" (uiop:native-namestring (merge-pathnames "tools/load.lisp" extracted)))
               (loop for form in forms append (list "--eval" form)))
       :directory extracted :environment environment :output :inherit :error-output :inherit))

(defun supervised (root environment script &rest arguments)
  "Run `sbcl --script SCRIPT ARGUMENTS` under the process supervisor, inheriting output."
  (run (append (list "sbcl" "--script"
                     (uiop:native-namestring (merge-pathnames "scripts/test-processes/test-processes.lisp" root))
                     "sbcl" "--script" (uiop:native-namestring script))
               arguments)
       :directory root :environment environment :output :inherit :error-output :inherit))

(defun main ()
  (let* ((arguments (rest sb-ext:*posix-argv*))
         (examples (member "--examples" arguments :test #'string=))
         (root (directory-above *load-truename* 2))
         (started (monotonic-seconds))
         (output (merge-pathnames "dist/" root))
         (archive (merge-pathnames "libtmux-source.tar.gz" output))
         (qlot-setup (merge-pathnames ".qlot/setup.lisp" root))
         (evidence '()))
    (ensure-directories-exist output)
    (let ((digest (build-archive root archive)))
      (with-temporary-directory (destination "libtmux-lisp-consumer")
        (run (list "tar" "-xzf" (uiop:native-namestring archive) "-C" (uiop:native-namestring destination)
                   "--no-same-owner"))
        (let* ((extracted (merge-pathnames "libtmux/" destination))
               (environment
                 (environment-with
                  (sb-ext:posix-environ)
                  "CL_SOURCE_REGISTRY" (format nil "(:source-registry (:directory ~S) :ignore-inherited-configuration)"
                                               (uiop:native-namestring extracted))
                  "ASDF_OUTPUT_TRANSLATIONS" (format nil "(:output-translations (t ~S) :ignore-inherited-configuration)"
                                                     (uiop:native-namestring (merge-pathnames "fasl/" destination)))
                  "LIBTMUX_QLOT_SETUP" nil))
               (qlot-environment (environment-with environment "LIBTMUX_QLOT_SETUP"
                                                   (uiop:native-namestring qlot-setup))))
          (dolist (check (consumer-checks extracted))
            (destructuring-bind (name qlot forms) check
              (run-consumer extracted (if qlot qlot-environment environment) forms)
              (push (cons name "PASS") evidence)))
          (when examples
            (flet ((suites (&rest suites)
                     (apply #'supervised root qlot-environment
                            (merge-pathnames "tools/test.lisp" extracted) suites)))
              (suites "workspace" "control-integration" "configuration-integration" "workspace-integration")
              (suites "workspace-inspection-integration")
              (suites "workspace-writer-integration")
              (dolist (suite '("workspace-apply-integration" "workspace-publication-integration"
                               "workspace-apply-race-integration" "workspace-public-integration"))
                (suites suite)))
            (run (list "sbcl" "--script"
                       (uiop:native-namestring (merge-pathnames "scripts/doc-examples/doc-examples.lisp" extracted)))
                 :directory extracted :environment qlot-environment :output :inherit :error-output :inherit)
            (run (list "sbcl" "--script"
                       (uiop:native-namestring (merge-pathnames "scripts/examples/examples.lisp" extracted)))
                 :directory root :environment qlot-environment :output :inherit :error-output :inherit)
            (uiop:copy-file (merge-pathnames "dist/examples-evidence.json" extracted)
                            (merge-pathnames "examples-evidence.json" output)))))
      (let ((result (append (list (cons "artifact" (file-namestring archive)) (cons "sha256" digest)
                                  (cons "elapsed_seconds" (/ (round (* 1000 (- (monotonic-seconds) started))) 1000d0)))
                            (reverse evidence)
                            (when examples
                              (loop for name in '("archived_examples" "archived_control_integration"
                                                  "archived_configuration_integration"
                                                  "archived_workspace_integration" "archived_workspace_unit"
                                                  "archived_workspace_inspection_integration"
                                                  "archived_workspace_writer_integration"
                                                  "archived_workspace_apply_integration"
                                                  "archived_workspace_public_integration"
                                                  "archived_workspace_publication_integration"
                                                  "archived_workspace_apply_race_integration")
                                    collect (cons name "PASS")))
                            (list (cons "optional_source" "archive")))))
        (json-write-file (merge-pathnames "package-evidence.json" output) (cons :object result))
        (format t "~A~%" (json-string (cons :object result) :indent nil))
        0))))

(main-when-script #'main)
