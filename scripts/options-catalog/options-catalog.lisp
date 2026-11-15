;;; Generate src/options-catalog.lisp, the native option contracts, from
;;; data/options-catalog.json, the pinned and compiled-source-checked facts.
;;;
;;;   sbcl --script scripts/options-catalog/options-catalog.lisp [check|write]
;;;   sbcl --script scripts/options-catalog/options-catalog.lisp import \
;;;       --source-catalog build/options-catalog/catalog.json
;;;
;;; check (default) fails when the generated file is stale; `mise run check`
;;; runs it. write regenerates it (`mise run catalogs`). import folds the
;;; catalog that scripts/options-catalog/extract-options-catalog.lisp wrote into
;;; data/options-catalog.json, then regenerates.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))
(unless (find-package "CL-PPCRE")
  (asdf:load-system "cl-ppcre"))

(defpackage #:libtmux.scripts.options-catalog
  (:use #:cl #:libtmux.scripts)
  (:export #:validate #:import-source #:render #:supported-pins))

(in-package #:libtmux.scripts.options-catalog)

(defparameter *contract-fields*
  '("name" "declared_type" "value_representation" "declared_scopes" "native_scopes" "flags"
    "array" "hook" "minimum" "maximum" "choices" "separator" "pattern" "pattern_language" "unit"))

(defun input-path (root) (merge-pathnames "data/options-catalog.json" root))
(defun output-path (root) (merge-pathnames "src/options-catalog.lisp" root))
(defun sources-path (root) (merge-pathnames "tools/tmux-sources.json" root))

(defun supported-pins (root)
  (remove-if-not (lambda (cell) (equal "supported" (jref cell "purpose")))
                 (coerce (jref (json-read-file (sources-path root)) "cells") 'list)))

(defun validate (data root)
  (unless (equal "libtmux.option-contracts/1" (jref data "schema"))
    (fail "Unknown option-contract schema"))
  (unless (equal (jref data "provenance" "tmux_sources_sha256") (sha256-file (sources-path root)))
    (fail "tmux source pins changed; extract and review the option catalog again"))
  (unless (equal (map 'list (lambda (v) (list (jref v "version") (jref v "commit")))
                      (jref data "versions"))
                 (mapcar (lambda (pin) (list (jref pin "tmux") (jref pin "commit")))
                         (supported-pins root)))
    (fail "Option catalogs do not cover the exact supported source pins"))
  (loop for version across (jref data "versions")
        do (unless (= (length (jref version "contracts")) (length (jref version "source_lines")))
             (fail "Option source locations do not match contract entries"))
           (let ((names (map 'list (lambda (index) (jref data "contracts" index "name"))
                             (jref version "contracts"))))
             (unless (= (length names) (length (remove-duplicates names :test #'string=)))
               (fail "Duplicate canonical option name"))
             (loop for alias across (jref version "aliases")
                   do (unless (member (jref alias "to") names :test #'string=)
                        (fail "Alias does not name a declared option"))))))

(defun import-source (path root)
  "Fold the extractor's catalog at PATH into data/options-catalog.json; return the data."
  (let ((source (json-read-file path))
        (contracts '()) (indices (make-hash-table :test #'equal)) (versions '()))
    (unless (equal "libtmux.native-options-catalog/1" (jref source "schema"))
      (fail "Expected the pinned tmux source extractor's catalog"))
    (loop for version across (jref source "versions")
          do (let ((ids '()) (lines '()))
               (loop for entry across (jref version "options")
                     do (let* ((contract (cons :object (mapcar (lambda (field)
                                                                (cons field (jref entry field)))
                                                              *contract-fields*)))
                               (key (json-string contract :indent nil :sort-keys t)))
                          (unless (gethash key indices)
                            (setf (gethash key indices) (length contracts))
                            (setf contracts (append contracts (list contract))))
                          (push (gethash key indices) ids)
                          (push (jref entry "source" "line") lines)))
               (push (obj "version" (jref version "version") "commit" (jref version "commit")
                          "capabilities" (jref version "capabilities")
                          "aliases" (jref version "aliases")
                          "contracts" (coerce (nreverse ids) 'vector)
                          "source_lines" (coerce (nreverse lines) 'vector))
                     versions)))
    (let ((data (obj "schema" "libtmux.option-contracts/1"
                     "provenance" (obj "catalog_sha256" (sha256-file path)
                                       "tmux_sources_sha256" (jref source "source_catalog_sha256")
                                       "default_values" "omitted" "descriptions" "omitted"
                                       "source_file" "options-table.c")
                     "contracts" (coerce contracts 'vector)
                     "versions" (coerce (nreverse versions) 'vector))))
      (validate data root)
      (json-write-file (input-path root) data)
      data)))

(defun lisp-string (value)
  "A Lisp string literal; Lisp strings do not use JSON or C escapes for control characters."
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for character across value
          do (when (member character '(#\\ #\")) (write-char #\\ out))
             (write-char character out))
    (write-char #\" out)))

(defun keyword-text (value)
  (unless (cl-ppcre:scan "^[a-z][a-z0-9-]*$" value)
    (fail "Unexpected schema keyword: ~S" value))
  (concatenate 'string ":" value))

(defun scalar (value)
  (cond ((member value '(:null :false)) "nil")
        ((eq value :true) "t")
        ((integerp value) (format nil "~D" value))
        ((stringp value) (lisp-string value))
        ((vectorp value) (format nil "(~{~A~^ ~})" (map 'list #'scalar value)))
        (t (fail "Unsupported data value: ~S" value))))

(defun render (data root)
  (let ((lines (list ";;; Generated by scripts/options-catalog/options-catalog.lisp; edit the pinned source facts instead."
                     (format nil ";;; Input SHA256: ~A" (sha256-file (input-path root)))
                     "(in-package #:libtmux.internal)" ""
                     "(defparameter *option-contract-data*" "  '(")))
    (flet ((add (line) (setf lines (append lines (list line)))))
      (loop for entry across (jref data "contracts")
            do (add (format nil "    (~{~A~^ ~})"
                            (append
                             (list ":name" (lisp-string (jref entry "name"))
                                   ":kind" (keyword-text (jref entry "declared_type"))
                                   ":representation" (keyword-text (jref entry "value_representation"))
                                   ":scopes" (format nil "(~{~A~^ ~})"
                                                     (map 'list #'keyword-text (jref entry "native_scopes")))
                                   ":flags" (format nil "(~{~A~^ ~})"
                                                    (map 'list #'keyword-text (jref entry "flags"))))
                             (loop for (key field) in '((":array-p" "array") (":hook-p" "hook")
                                                        (":minimum" "minimum") (":maximum" "maximum")
                                                        (":choices" "choices") (":separator" "separator")
                                                        (":pattern" "pattern")
                                                        (":pattern-language" "pattern_language")
                                                        (":unit" "unit"))
                                   append (list key (scalar (jref entry field))))))))
      (add "    ))")
      (add "")
      (add "(defparameter *option-catalog-data*")
      (add "  '(")
      (loop for version across (jref data "versions")
            for capabilities = (jref version "capabilities")
            do (add (format nil "    (~A ~A" (lisp-string (jref version "version"))
                            (lisp-string (jref version "commit"))))
               (add (format nil "     (~{~D~^ ~})" (coerce (jref version "contracts") 'list)))
               (add (format nil "     (~{~D~^ ~})" (coerce (jref version "source_lines") 'list)))
               (add (format nil "     (~{(~A ~A)~^ ~})"
                            (loop for alias across (jref version "aliases")
                                  append (list (lisp-string (jref alias "from"))
                                               (lisp-string (jref alias "to"))))))
               (add (format nil "     (:formatted-p ~A :string-keys-p ~A :numeric-key-maximum ~A :user-event-hooks-p ~A))"
                            (scalar (jref capabilities "show_options_format"))
                            (scalar (if (equal "integer-or-string" (jref capabilities "array_key_kind"))
                                        :true :false))
                            (scalar (jref capabilities "array_numeric_key_maximum"))
                            (scalar (jref capabilities "user_event_hooks")))))
      (add "    ))")
      (add ""))
    (format nil "~{~A~^~%~}" lines)))

(defun main ()
  (let* ((arguments (rest sb-ext:*posix-argv*))
         (mode (or (first arguments) "check"))
         (root (directory-above *load-truename* 2))
         (source-catalog (second (member "--source-catalog" arguments :test #'string=))))
    (unless (member mode '("check" "write" "import") :test #'string=)
      (fail "Usage: options-catalog.lisp [check|write|import --source-catalog PATH]"))
    (when (and (string= mode "import") (null source-catalog))
      (fail "import requires --source-catalog"))
    (let* ((data (if (string= mode "import")
                     (import-source (merge-pathnames source-catalog (uiop:getcwd)) root)
                     (let ((data (json-read-file (input-path root))))
                       (validate data root)
                       data)))
           (expected (render data root))
           (output (output-path root)))
      (if (string= mode "check")
          (unless (and (probe-file output) (string= (read-text output) expected))
            (fail "Stale native option catalog; run mise run catalogs"))
          (write-text output expected))
      (format t "Native catalogs: ~D versions, ~D distinct contracts, ~D entries: PASS~%"
              (length (jref data "versions")) (length (jref data "contracts"))
              (reduce #'+ (map 'list (lambda (v) (length (jref v "contracts"))) (jref data "versions"))))
      0)))

(main-when-script #'main)
