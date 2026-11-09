(defpackage #:libtmux.tests
  (:use #:cl #:fiveam)
  (:export #:run-suite))

(in-package #:libtmux.tests)

(def-suite unit)
(def-suite query)
(def-suite regex)
(def-suite json)
(def-suite control)
(def-suite workspace)
(def-suite integration)
(def-suite control-integration)
(def-suite configuration-integration)

(defun run-suite (name)
  (run! (ecase name
          (:unit 'unit)
          (:query 'query)
          (:regex 'regex)
          (:json 'json)
          (:control 'control)
          (:control-integration 'control-integration)
          (:configuration-integration 'configuration-integration)
          (:workspace 'workspace)
          (:integration 'integration))))
