(defpackage #:libtmux.tests
  (:use #:cl #:fiveam)
  (:export #:run-suite))

(in-package #:libtmux.tests)

(def-suite unit)
(def-suite query)
(def-suite regex)
(def-suite json)
(def-suite workspace)
(def-suite integration)

(defun run-suite (name)
  (run! (ecase name
          (:unit 'unit)
          (:query 'query)
          (:regex 'regex)
          (:json 'json)
          (:workspace 'workspace)
          (:integration 'integration))))
