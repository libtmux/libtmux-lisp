(in-package #:libtmux.tests)

(in-suite scripts)

(defun artifact-header (&key (port "lisp") (sha (make-string 64 :initial-element #\0)))
  "An artifact that passes every check before the package inventory."
  (libtmux.scripts:obj
   "schema" "libtmux.lisp.api/1" "port" port
   "source" (libtmux.scripts:obj "repository" "libtmux/libtmux-lisp" "revision" "abc"
                                 "dirty" :false
                                 "files" (vector (libtmux.scripts:obj
                                                  "path" "tools/documentation.lisp" "sha256" sha)))
   "exporter" (libtmux.scripts:obj "name" "libtmux.documentation" "version" 1
                                   "revision" (make-string 40 :initial-element #\a) "dirty" :false)
   "library" (libtmux.scripts:obj "version" "0.1.0")
   "runtime" (libtmux.scripts:obj "implementation" "SBCL" "implementationVersion" "2.6.10"
                                  "asdfVersion" "3.3.7")
   "packages" (vector)))

(defun artifact-failure (artifact)
  (handler-case
      (progn (libtmux.scripts.check-documentation-artifact:check-artifact
              artifact (asdf:system-source-directory "libtmux") :revision "abc")
             nil)
    (libtmux.scripts:script-failure (condition) (princ-to-string condition))))

(test artifact-check-rejects-another-port-and-stale-source-hashes
  (is (equal "documentation artifact: wrong port"
             (artifact-failure (artifact-header :port "ruby"))))
  (is (equal "documentation artifact: stale source hash for tools/documentation.lisp"
             (artifact-failure (artifact-header)))))
