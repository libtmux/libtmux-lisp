(in-package #:libtmux.tests)

(in-suite scripts)

(defun repository-root () (asdf:system-source-directory "libtmux"))

(test generated-option-catalog-is-the-render-of-its-committed-facts
  (let* ((root (repository-root))
         (data (libtmux.scripts:json-read-file (merge-pathnames "data/options-catalog.json" root))))
    (libtmux.scripts.options-catalog:validate data root)
    (is (string= (libtmux.scripts:read-text (merge-pathnames "src/options-catalog.lisp" root))
                 (libtmux.scripts.options-catalog:render data root)))))

(test option-catalog-refuses-facts-that-no-longer-match-the-source-pins
  (let* ((root (repository-root))
         (data (libtmux.scripts:json-read-file (merge-pathnames "data/options-catalog.json" root)))
         (provenance (libtmux.scripts:jhas data "provenance")))
    (setf (cdr (libtmux.scripts:jhas (cdr provenance) "tmux_sources_sha256")) "stale")
    (signals libtmux.scripts:script-failure
      (libtmux.scripts.options-catalog:validate data root))))

(test extractor-reads-the-restricted-c-grammar-and-rejects-the-rest
  (let ((lex #'libtmux.scripts.extract-options-catalog:lex))
    (is (= 10 (libtmux.scripts.extract-options-catalog:integer-value
               (coerce (funcall lex "(1 << 3) | 2") 'list))))
    (is (string= (format nil "a~Cλ" #\Newline)
                 (libtmux.scripts.extract-options-catalog:c-string
                  (list (format nil "\"a\\n\"") (format nil "\"\\316\\273\"")))))
    (is (equal '("OPTIONS_TABLE_IS_ARRAY" "OPTIONS_TABLE_IS_HOOK")
               (libtmux.scripts.extract-options-catalog:symbolic-bits
                '("OPTIONS_TABLE_IS_ARRAY" "|" "OPTIONS_TABLE_IS_HOOK")
                '(("OPTIONS_TABLE_IS_ARRAY" . "array") ("OPTIONS_TABLE_IS_HOOK" . "hook")))))
    (let ((checks (libtmux.scripts.extract-options-catalog:rejected-construct-checks)))
      (is (= 6 (length checks))))))
