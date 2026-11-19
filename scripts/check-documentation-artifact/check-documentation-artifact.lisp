;;; Validate the native Common Lisp API artifact and its source identity.
;;;
;;;   sbcl --script scripts/check-documentation-artifact/check-documentation-artifact.lisp
;;;
;;; Reads docs/_build/api.json, which `sbcl --script tools/documentation.lisp
;;; artifact` writes, and fails when its revision, source hashes, package
;;; inventory, declarations or capability directory are wrong or stale. Run by
;;; `mise run check` and `mise run docs-artifact`.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))
(unless (find-package "CL-PPCRE")
  (asdf:load-system "cl-ppcre"))
(unless (find-package "LIBTMUX.SCRIPTS.API-DIRECTORY")
  (load (merge-pathnames "../api-directory/api-directory.lisp" *load-truename*)))

(defpackage #:libtmux.scripts.check-documentation-artifact
  (:use #:cl #:libtmux.scripts)
  (:export #:check-artifact #:check-directory))

(in-package #:libtmux.scripts.check-documentation-artifact)

(defparameter *packages*
  '("libtmux" "libtmux.control" "libtmux.json" "libtmux.query" "libtmux.workspace"
    "libtmux.workspace.cli"))

(defparameter *required-symbols*
  '("libtmux.control:open-connection" "libtmux.control:await-request"
    "libtmux.control:next-event" "libtmux:fetch-snapshot" "libtmux:window-link"
    "libtmux.query:compile-filter" "libtmux.json:read-filter"
    "libtmux.workspace:apply-workspace" "libtmux.workspace.cli:main"))

(defun require-that (condition control &rest arguments)
  (unless condition
    (fail "documentation artifact: ~?" control arguments)))

(defun field (object key &optional default)
  "Return OBJECT's KEY, or DEFAULT when OBJECT has no such member."
  (let ((cell (jhas object key))) (if cell (cdr cell) default)))

(defun truthy (value)
  (not (or (null value) (eq value :false) (eq value :null) (equal value "")
           (and (vectorp value) (not (stringp value)) (zerop (length value))))))

(defun booleanp* (value) (member value '(:true :false)))

(defun sha-p (string)
  (and (stringp string) (= 40 (length string))
       (every (lambda (c) (digit-char-p c 16)) string)
       (string= string (string-downcase string))))

(defun declaration-lines (source name)
  "Return the 1-based lines of SOURCE that declare NAME."
  (let ((scanner (cl-ppcre:create-scanner
                  (format nil "^[ \\t]*\\((?:defun|defmacro|defgeneric|defmethod|defclass|define-condition)[ \\t]+(?:[\\w.+-]+::?)?~A(?=[\\s(])"
                          (cl-ppcre:quote-meta-chars name))
                  :case-insensitive-mode t :multi-line-mode t)))
    (loop for (start nil) on (cl-ppcre:all-matches scanner source) by #'cddr
          collect (1+ (count #\Newline source :end start)))))

(defun required-parameters (signature)
  "Return the names a printed lambda list requires, before any keyword."
  (let ((registers (nth-value 1 (cl-ppcre:scan-to-strings
                                 "^\\(\\S+((?: [^\\s&(][^\\s)]*)*)" signature))))
    (and registers (remove "" (cl-ppcre:split "\\s+" (aref registers 0))
                           :test #'string=))))

(defun entity-operations (symbols noun ancestors)
  "Return the identities of the functions in SYMBOLS that take a NOUN.
A function takes one when a required parameter is named NOUN or ends in -NOUN,
or when a method specializes on one of ANCESTORS."
  (loop for symbol in symbols
        when (and (equal "function" (field symbol "kind"))
                  (or (some (lambda (name)
                              (or (string-equal name noun)
                                  (uiop:string-suffix-p name (format nil "-~A" noun))))
                            (required-parameters (field symbol "signature" "")))
                      (some (lambda (method)
                              (intersection ancestors
                                            (coerce (field method "specializers" (vector)) 'list)
                                            :test #'equal))
                            (field symbol "methods" (vector)))))
          collect (field symbol "id")))

(defun check-directory (id body ids operations)
  "Require BODY, the docstring body of class ID, to hold one capability directory.
It may name only public symbols from IDS and must name every one of OPERATIONS."
  (multiple-value-bind (runs strays) (libtmux.scripts.api-directory:fold body)
    (require-that (and (= 1 (length runs)) (null strays))
                  "~A lost its capability directory: need three or more bold-led paragraphs, each followed by a references-only paragraph (folded ~D, left as prose ~S)"
                  id (length runs) strays)
    (let* ((listed (loop for (nil references) in (first runs) append references))
           (unknown (set-difference listed ids :test #'equal))
           (missing (set-difference operations listed :test #'equal)))
      (require-that (null unknown) "~A directory references unknown symbols: ~S"
                    id (sort unknown #'string<))
      (require-that (null missing) "~A directory omits operations that take it: ~S"
                    id (sort missing #'string<)))))

(defun check-artifact (artifact root &key (revision (git root "rev-parse" "HEAD")))
  "Check parsed ARTIFACT against the checkout at ROOT; return a one-line summary."
  (let* ((source (field artifact "source" (obj)))
         (exporter (field artifact "exporter" (obj)))
         (library (field artifact "library" (obj)))
         (runtime (field artifact "runtime" (obj)))
         (packages (coerce (field artifact "packages" (vector)) 'list))
         (files (coerce (field source "files" (vector)) 'list)))
    (require-that (equal "libtmux.lisp.api/1" (field artifact "schema")) "unsupported schema")
    (require-that (equal "lisp" (field artifact "port")) "wrong port")
    (require-that (equal "libtmux/libtmux-lisp" (field source "repository")) "wrong repository")
    (require-that (equal revision (field source "revision")) "stale source revision")
    (require-that (booleanp* (field source "dirty")) "source dirty state is missing")
    (require-that (equal "libtmux.documentation" (field exporter "name")) "wrong exporter")
    (require-that (eql 1 (field exporter "version")) "wrong exporter version")
    (require-that (sha-p (field exporter "revision" "")) "invalid exporter revision")
    (require-that (booleanp* (field exporter "dirty")) "exporter dirty state is missing")
    (require-that (equal "0.1.0" (field library "version")) "wrong ASDF system version")
    (require-that (equal "SBCL" (field runtime "implementation")) "wrong Lisp implementation")
    (require-that (truthy (field runtime "implementationVersion"))
                  "missing Lisp implementation version")
    (require-that (equal "3.3.7" (field runtime "asdfVersion")) "wrong ASDF producer version")
    (let ((file-paths (mapcar (lambda (entry) (field entry "path")) files)))
      (require-that (equal file-paths (sort (remove-duplicates (copy-list file-paths) :test #'equal)
                                            #'string<))
                    "source files are not sorted and unique")
      (require-that (member "tools/documentation.lisp" file-paths :test #'equal)
                    "exporter source is absent")
      (dolist (entry files)
        (let ((path (merge-pathnames (field entry "path") root)))
          (require-that (probe-file path) "missing source file ~A" (field entry "path"))
          (require-that (equal (sha256-file path) (field entry "sha256"))
                        "stale source hash for ~A" (field entry "path"))))
      (flet ((dirty-p (&rest paths)
               (plusp (length (apply #'git root "status" "--porcelain" "--" paths)))))
        (require-that (eq (if (apply #'dirty-p file-paths) :true :false) (field source "dirty"))
                      "source dirty state is stale")
        (require-that (eq (if (dirty-p "tools/documentation.lisp") :true :false)
                          (field exporter "dirty"))
                      "exporter dirty state is stale"))
      (require-that (equal *packages* (mapcar (lambda (package) (field package "name")) packages))
                    "public package inventory differs")
      (let* ((symbols (loop for package in packages
                            append (coerce (field package "symbols" (vector)) 'list)))
             (ids (mapcar (lambda (symbol) (field symbol "id")) symbols))
             (by-id (make-hash-table :test #'equal))
             (sources (make-hash-table :test #'equal)))
        (loop for symbol in symbols for id in ids do (setf (gethash id by-id) symbol))
        (require-that (= (length ids) (hash-table-count by-id)) "duplicate public symbol identity")
        (require-that (subsetp *required-symbols* ids :test #'equal)
                      "required public declarations are absent")
        (require-that (notany (lambda (id) (search "internal" id)) ids) "private symbols escaped")
        (require-that (notany (lambda (id) (search "mcp" id)) ids) "excluded MCP API escaped")
        (dolist (symbol symbols)
          (let* ((id (field symbol "id")) (kind (field symbol "kind")) (name (field symbol "name"))
                 (location (field symbol "source" (obj))) (line (field location "line")))
            (require-that (member kind '("function" "class" "exception") :test #'equal)
                          "invalid kind for ~A" id)
            (require-that (truthy name) "missing name for ~A" id)
            (require-that (truthy (field (field symbol "documentation" (obj)) "summary"))
                          "missing summary for ~A" id)
            (require-that (member (field location "file") file-paths :test #'equal)
                          "untracked source for ~A" id)
            (require-that (and (integerp line) (plusp line)) "missing source line for ~A" id)
            (let ((lines (declaration-lines
                          (or (gethash (field location "file") sources)
                              (setf (gethash (field location "file") sources)
                                    (read-text (merge-pathnames (field location "file") root))))
                          name)))
              (when lines
                (require-that (member line lines) "source line does not name ~A" id)))
            (when (equal kind "function")
              (require-that (truthy (field symbol "signature")) "missing native signature for ~A" id)
              (when (eq :true (field symbol "generic"))
                (require-that (truthy (field symbol "methods")) "missing CLOS methods for ~A" id)
                (loop for method across (field symbol "methods")
                      do (require-that (truthy (field method "signature"))
                                       "missing method signature for ~A" id)
                         (require-that (vectorp (field method "qualifiers"))
                                       "missing method qualifiers for ~A" id)
                         (require-that (every (lambda (target)
                                                (or (equal target "common-lisp:t")
                                                    (gethash target by-id)))
                                              (field method "specializers" (vector)))
                                       "non-public method specializer for ~A" id))))))
        (flet ((symbol-for (id) (gethash id by-id))
               (specializers (symbol)
                 (map 'list (lambda (method) (coerce (field method "specializers") 'list))
                      (field symbol "methods" (vector)))))
          (let ((panes (specializers (symbol-for "libtmux:panes"))))
            (require-that (and (= 2 (length panes))
                               (member '("libtmux:snapshot") panes :test #'equal)
                               (member '("libtmux:window/type") panes :test #'equal))
                          "pane traversal lost snapshot/window method applicability"))
          (require-that (equal '(("libtmux:entity" "common-lisp:t"))
                               (specializers (symbol-for "libtmux:field-value")))
                        "field lookup lost its unspecialized second required argument")
          (require-that (find "libtmux.workspace:result-outcomes"
                              (field (field (symbol-for "libtmux.workspace:apply-workspace")
                                            "documentation") "seeAlso" (vector))
                              :test #'equal)
                        "authored API cross-reference was not preserved")
          (let ((see-also (coerce (field (field (symbol-for "libtmux.workspace.cli:main")
                                                "documentation")
                                         "seeAlso" (vector))
                                  'list)))
            (require-that (subsetp '("libtmux.workspace:apply-workspace" "libtmux:outcome-status"
                                     "libtmux:outcome-phase")
                                   see-also :test #'equal)
                          "workspace CLI lost authored references to another public package"))
          (flet ((directory-body (id)
                   (field (field (symbol-for id) "documentation") "body" "")))
            (check-directory
             "libtmux:client" (directory-body "libtmux:client") ids
             (loop for symbol in symbols
                   for id = (field symbol "id")
                   when (and (equal "function" (field symbol "kind"))
                             (uiop:string-prefix-p "libtmux:" id)
                             (cl-ppcre:scan "^\\([^ )]+ client[ )]"
                                            (field symbol "signature" "")))
                     collect id))
            (loop for (id noun) in '(("libtmux:session/type" "session")
                                     ("libtmux:window/type" "window")
                                     ("libtmux:pane" "pane"))
                  do (check-directory
                      id (directory-body id) ids
                      (entity-operations symbols noun (list id "libtmux:entity")))))
          (let ((reference (read-text (merge-pathnames "docs/workspace-api.md" root))))
            (dolist (anchor '("outcome-status-function" "outcome-phase-function"))
              (require-that (search (format nil "(api.md#~A)" anchor) reference)
                            "workspace reference does not link the core ~A" anchor))))
        (format nil "Native Common Lisp documentation artifact: PASS (~D packages, ~D declarations, ~D inputs)"
                (length packages) (length symbols) (length files))))))

(defun main ()
  (let* ((root (directory-above *load-truename* 2))
         (path (merge-pathnames "docs/_build/api.json" root)))
    (unless (probe-file path) (fail "documentation artifact: missing docs/_build/api.json"))
    (format t "~A~%" (check-artifact (json-read-file path) root))
    0))

(main-when-script #'main)
