(in-package #:libtmux.tests)

(in-suite scripts)

(test source-check-reports-trailing-whitespace-and-a-missing-final-newline
  (is (equal '("a.md:1: trailing whitespace" "a.md: missing final newline")
             (libtmux.scripts.check-source:check-text "a.md" (format nil "a ~%b"))))
  (is (equal '("a.lisp:2: trailing whitespace")
             (libtmux.scripts.check-source:check-text "a.lisp" (format nil "a~%~C~%b~%" #\Tab))))
  (is (null (libtmux.scripts.check-source:check-text "ok.md" (format nil "a~%~%b~%")))))

(test source-check-refuses-shell-and-python-scripts
  (flet ((language (name text) (libtmux.scripts.check-source:check-language name text)))
    (is (language "tools/run.sh" ""))
    (is (language "tools/run.py" ""))
    (is (language "tools/run" (format nil "#!/bin/sh~%true~%")))
    (is (language "tools/run" (format nil "#!/usr/bin/env python3~%pass~%")))
    (is (null (language "tools/run.lisp" (format nil "#!/usr/bin/env sbcl --script~%(print 1)~%"))))
    (is (null (language "tools/run.lisp" (format nil ";;; no shebang~%"))))))
