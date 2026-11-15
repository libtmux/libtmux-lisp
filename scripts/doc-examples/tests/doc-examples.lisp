(in-package #:libtmux.tests)

(in-suite scripts)

(defun write-fixture-file (root name text)
  (libtmux.scripts:write-text (merge-pathnames name root) text))

(test excerpts-follow-the-example-source-and-broken-links-are-reported
  (libtmux.scripts:with-temporary-directory (root "libtmux-doc-examples")
    (dolist (name '("query" "regex" "json" "control" "workspace" "workspace/cli"))
      (write-fixture-file root (format nil "~A/README.md" name) (format nil "# ~A~%" name)))
    (write-fixture-file root "examples/a.lisp"
                        (format nil ";;; docs:greet~%(print :hello)~%;;; docs:end~%"))
    (write-fixture-file root "README.md"
                        (format nil "# Title~%~%<!-- example:greet -->~%old~%<!-- /example -->~%~%[gone](missing.md) [here](#title)~%"))
    (let ((errors (libtmux.scripts.doc-examples:check-documents root)))
      (is (equal '("Stale example excerpt: README.md" "Broken local link in README.md: missing.md")
                 errors)))
    (is (equal '("Broken local link in README.md: missing.md")
               (libtmux.scripts.doc-examples:check-documents root :write t)))
    (is (search (format nil "```lisp~%(print :hello)~%```")
                (libtmux.scripts:read-text (merge-pathnames "README.md" root))))
    (write-fixture-file root "docs/guide.md" (format nil "<!-- example:absent -->~%<!-- /example -->~%"))
    (signals libtmux.scripts:script-failure
      (libtmux.scripts.doc-examples:check-documents root))))
