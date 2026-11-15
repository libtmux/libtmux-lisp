(in-package #:libtmux.tests)

(in-suite scripts)

(test source-archive-holds-the-tools-and-no-second-language-and-is-reproducible
  (let* ((root (asdf:system-source-directory "libtmux"))
         (names (libtmux.scripts.package:source-files root)))
    (dolist (name '("libtmux.asd" "tools/load.lisp" "scripts/package/package.lisp"
                    "examples/worker.lisp" "tests/child.lisp"))
      (is (member name names :test #'string=) "~A is missing from the archive" name))
    (is (notany (lambda (name) (member (pathname-type name) '("py" "sh") :test #'equal)) names))
    (libtmux.scripts:with-temporary-directory (directory "libtmux-package-test")
      (let ((first (merge-pathnames "one.tar.gz" directory))
            (second (merge-pathnames "two.tar.gz" directory)))
        (is (string= (libtmux.scripts.package::build-archive root first)
                     (libtmux.scripts.package::build-archive root second)))))))
