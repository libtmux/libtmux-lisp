(require :asdf)
(require :sb-introspect)
(asdf:load-asd (truename "libtmux.asd"))
(asdf:load-system "libtmux")
(asdf:load-system "libtmux/query")
(asdf:load-system "libtmux/regex")
(asdf:load-system "libtmux/json")
(asdf:load-system "libtmux/workspace/cli")

(defpackage #:libtmux.documentation
  (:use #:cl)
  (:local-nicknames (#:internal #:libtmux.internal)))
(in-package #:libtmux.documentation)

(defparameter *artifact-packages*
  '(("libtmux" :libtmux "libtmux" "core" "src/package.lisp")
    ("libtmux.json" :libtmux.json "libtmux/json" "core" "src/json.lisp")
    ("libtmux.query" :libtmux.query "libtmux/query" "core" "src/query.lisp")
    ("libtmux.workspace" :libtmux.workspace "libtmux/workspace" "workspace"
     "src/workspace.lisp")
    ("libtmux.workspace.cli" :libtmux.workspace.cli "libtmux/workspace/cli"
     "workspace" "src/workspace-cli.lisp")))

(defun public-symbols (&optional (package :libtmux))
  (sort (loop for symbol being the external-symbols of (find-package package)
              collect symbol) #'string< :key #'symbol-name))

(defun spelling (symbol)
  (string-downcase (symbol-name symbol)))

(defun api-anchor (symbol)
  (cond ((fboundp symbol) (format nil "#~A-function" (spelling symbol)))
        ((find-class symbol nil) (format nil "#~A-type" (spelling symbol)))))

(defun reference-page (package)
  (or (cdr (assoc (package-name (find-package package))
                  '(("LIBTMUX" . "api.md")
                    ("LIBTMUX.QUERY" . "query-api.md")
                    ("LIBTMUX.JSON" . "json-api.md")
                    ("LIBTMUX.WORKSPACE" . "workspace-api.md")
                    ("LIBTMUX.WORKSPACE.CLI" . "workspace-api.md"))
                  :test #'string=))
      (error "No public reference page for package ~A" package)))

(defun referenced-symbols (symbol references package)
  "Resolve authored names through public packages without reading or interning."
  (labels ((public-reference (name owner)
             (when owner
               (multiple-value-bind (candidate status) (find-symbol name owner)
                 (when (and (eq status :external) (api-anchor candidate)) candidate))))
           (resolve-reference (token)
             (let* ((colon (position #\: token))
                    (owner (and colon (find-package (subseq token 0 colon))))
                    (local (unless colon (public-reference token package)))
                    (matches
                      (cond
                        (colon
                         (when (member owner *artifact-packages*
                                       :key (lambda (spec) (find-package (second spec))))
                           (let ((candidate (public-reference (subseq token (1+ colon)) owner)))
                             (when candidate (list candidate)))))
                        (local (list local))
                        (t (remove-duplicates
                            (loop for spec in *artifact-packages*
                                  for candidate = (public-reference token (second spec))
                                  when candidate collect candidate))))))
               (unless (= 1 (length matches))
                 (error "Unknown or ambiguous public reference ~A in ~A" token symbol))
               (first matches))))
    (sort
     (remove-duplicates
      (loop for token in (uiop:split-string
                          references :separator '(#\Space #\Tab #\Newline #\Return #\,))
            for name = (string-upcase (string-right-trim "." token))
            when (plusp (length name))
              append (let ((candidate (resolve-reference name)))
                       (unless (eq candidate symbol) (list candidate)))))
     #'string< :key (lambda (candidate)
                     (format nil "~A:~A" (symbol-name candidate)
                             (package-name (symbol-package candidate)))))))

(defun see-also (symbol references &optional (package (symbol-package symbol)))
  "Build API-browser links from an explicit See also docstring line."
  (let ((references
          (loop for candidate in (referenced-symbols symbol references package)
                for page = (reference-page (symbol-package candidate))
                for local-p = (string= page (reference-page package))
                collect (format nil "[~A](~A~A)"
                                (if local-p (spelling candidate)
                                    (format nil "~(~A~):~A"
                                            (package-name (symbol-package candidate))
                                            (spelling candidate)))
                                (if local-p "" page) (api-anchor candidate)))))
    (when references
      (format nil "See also: ~{~A~^, ~}." references))))

(defun documentation-parts (symbol type &optional (package (symbol-package symbol)))
  "Return the prose body and linked references from SYMBOL's docstring."
  (let* ((documentation (required-documentation symbol type))
         (marker (format nil "~%See also: "))
         (position (search marker documentation :from-end t)))
    (if position
        (let ((related (see-also symbol
                                 (subseq documentation (+ position (length marker)))
                                 package)))
          (unless related
            (error "See also line has no public API references: ~A" symbol))
          (values (subseq documentation 0 position) related))
        (values documentation nil))))

(defun signature-text (value)
  (typecase value
    (symbol (format nil "~A~A" (if (keywordp value) ":" "") (spelling value)))
    (cons (format nil "(~{~A~^ ~})" (mapcar #'signature-text value)))
    (t (write-to-string value))))

(defun required-documentation (object type)
  (or (documentation object type)
      (error "Missing ~A documentation for ~A" type object)))

(defun definition-path (symbol kind)
  (let* ((source (first (sb-introspect:find-definition-sources-by-name symbol kind)))
         (path (and source (sb-introspect:definition-source-pathname source))))
    (unless path (error "Missing source location for ~A ~A" kind symbol))
    path))

(defun function-kind (symbol)
  (cond ((macro-function symbol) :macro)
        ((typep (fdefinition symbol) 'generic-function) :generic-function)
        (t :function)))

(defun source-link (symbol kind)
  (format nil "[Source](../~A)"
          (enough-namestring (definition-path symbol kind) (uiop:getcwd))))

(defparameter *index-groups*
  '(("Connect and manage lifetime" "client")
    ("Acquire, traverse and project captured graphs" "capture" "model")
    ("Inspect outcomes and cancel work" "transport")
    ("Create sessions, windows and panes" "creation")
    ("Operate on attached terminal clients" "client-operations")
    ("Coordinate server requests" "server-operations")
    ("Select, arrange and link targets" "geometry" "selection" "placement")
    ("Rename, capture, send input and manage pane processes"
     "operations" "terminal-operations" "process-operations")
    ("Read and write buffers and files" "buffers")
    ("Configure options, hooks and environment" "configuration-operations")
    ("Terminate explicit targets" "termination")
    ("Inspect failure evidence" "conditions")))

(defun git-output (&rest arguments)
  (string-right-trim
   '(#\Newline #\Return)
   (uiop:run-program (cons "git" arguments)
                     :output :string :error-output :string)))

(defun repository-path (pathname)
  (substitute #\/ #\\
              (enough-namestring (truename pathname) (truename (uiop:getcwd)))))

(defun artifact-source-files ()
  (sort
   (remove-duplicates
    (append (mapcar #'repository-path (directory "src/*.lisp"))
            (mapcar #'repository-path (directory "*.asd"))
            '("tools/documentation.lisp"))
    :test #'string=)
   #'string<))

(defun sha256-file (path)
  (first (uiop:split-string
          (uiop:run-program (list "sha256sum" path)
                            :output :string :error-output :string))))

(defun tracked-dirty-p (paths)
  (plusp (length (apply #'git-output "status" "--porcelain" "--" paths))))

(defun definition-source (symbol kind)
  (or (first (sb-introspect:find-definition-sources-by-name symbol kind))
      (error "Missing source location for ~A ~A" kind symbol)))

(defun top-level-form-offset (path index)
  "Return the byte offset of trusted source form INDEX in PATH."
  (with-open-file (stream path :direction :input)
    (let ((*package* (find-package :cl-user))
          (*read-eval* nil)
          (eof (gensym "EOF")))
      (loop for number from 0
            for offset = (file-position stream)
            for form = (read stream nil eof)
            until (eq form eof)
            when (= number index) return offset
            do (when (and (consp form) (eq (first form) 'in-package))
                 (setf *package*
                       (or (find-package (string (second form)))
                           (error "Unknown package in ~A: ~S" path (second form)))))
            finally (error "Source form ~D is absent from ~A" index path)))))

(defun declaration-head-p (head kind)
  (member head
          (ecase kind
            ((:function :macro :generic-function) '(defun defmacro defgeneric defmethod))
            (:class '(defclass defstruct))
            (:condition '(define-condition)))
          :test #'eq))

(defun declaration-marker-offset (path start end head symbol)
  "Locate the declaration marker between trusted reader positions START and END."
  (let ((marker (format nil "(~(~A~) ~(~A~)" head symbol)))
    (with-open-file (stream path :direction :input)
      (file-position stream start)
      (loop for line-offset = (file-position stream)
            while (< line-offset end)
            for line = (read-line stream nil nil)
            while line
            for position = (search marker line :test #'char-equal)
            when position return (+ line-offset position)
            finally (error "Cannot locate ~A declaration of ~A in ~A" head symbol path)))))

(defun direct-declaration-offsets (path symbol kind)
  "Return byte offsets of trusted top-level forms that declare SYMBOL as KIND."
  (with-open-file (stream path :direction :input)
    (let ((*package* (find-package :cl-user))
          (*read-eval* nil)
          (eof (gensym "EOF"))
          (offsets '()))
      (loop for offset = (file-position stream)
            for form = (read stream nil eof)
            until (eq form eof)
            do (when (and (consp form)
                          (declaration-head-p (first form) kind)
                          (let ((name (second form)))
                            (and (symbolp name) (eq name symbol))))
                 (push (declaration-marker-offset
                        path offset (file-position stream) (first form) symbol)
                       offsets))
               (when (and (consp form) (eq (first form) 'in-package))
                 (setf *package*
                       (or (find-package (string (second form)))
                           (error "Unknown package in ~A: ~S" path (second form)))))
            finally (return (nreverse offsets))))))

(defun closest-offset (offset candidates)
  (reduce (lambda (left right)
            (if (< (abs (- right offset)) (abs (- left offset))) right left))
          candidates))

(defun source-line (symbol kind source)
  (let* ((path (sb-introspect:definition-source-pathname source))
         (reported-offset
           (or (sb-introspect:definition-source-character-offset source)
               (let ((path-components
                       (sb-introspect:definition-source-form-path source)))
                 (and path-components
                      (top-level-form-offset path (first path-components))))))
         (declarations (and path (direct-declaration-offsets path symbol kind)))
         (offset (if declarations
                     (closest-offset (or reported-offset (first declarations)) declarations)
                     reported-offset)))
    (unless (and offset path) (error "Missing source position for ~A" path))
    (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
      (1+ (loop repeat offset
                for byte = (read-byte stream nil nil)
                while byte
                count (= byte 10))))))

(defun native-identity (symbol kind)
  (let* ((package (string-downcase (package-name (symbol-package symbol))))
         (name (spelling symbol))
         (collision (and (fboundp symbol) (find-class symbol nil))))
    (format nil "~A:~A~A" package name
            (if collision
                (ecase kind (:function "/function") (:type "/type"))
                ""))))

(defun documentation-structure (symbol type &optional (package (symbol-package symbol)))
  (let* ((documentation (required-documentation symbol type))
         (marker (format nil "~%See also: "))
         (position (search marker documentation :from-end t))
         (text (if position (subseq documentation 0 position) documentation))
         (references (and position
                          (referenced-symbols
                           symbol (subseq documentation (+ position (length marker)))
                           package)))
         (paragraph (search (format nil "~%~%") text))
         (summary (string-trim '(#\Space #\Tab #\Newline #\Return)
                               (if paragraph (subseq text 0 paragraph) text)))
         (body (and paragraph
                    (string-trim '(#\Space #\Tab #\Newline #\Return)
                                 (subseq text (+ paragraph 2))))))
    (values summary (and body (plusp (length body)) body) references)))

(defun write-string-array (writer values)
  (com.inuoe.jzon:with-array writer
    (dolist (value values) (com.inuoe.jzon:write-value writer value))))

(defun write-artifact-documentation (writer symbol type package)
  (multiple-value-bind (summary body references)
      (documentation-structure symbol type package)
    (com.inuoe.jzon:with-object writer
      (com.inuoe.jzon:write-key writer "summary")
      (com.inuoe.jzon:write-value writer summary)
      (when body
        (com.inuoe.jzon:write-key writer "body")
        (com.inuoe.jzon:write-value writer body))
      (when references
        (com.inuoe.jzon:write-key writer "seeAlso")
        (write-string-array
         writer
         (mapcar (lambda (reference)
                   (native-identity reference
                                    (if (fboundp reference) :function :type)))
                 references))))))

(defun write-artifact-source (writer symbol kind)
  (let ((source (definition-source symbol kind)))
    (com.inuoe.jzon:with-object writer
      (com.inuoe.jzon:write-key writer "file")
      (com.inuoe.jzon:write-value
       writer (repository-path (sb-introspect:definition-source-pathname source)))
      (com.inuoe.jzon:write-key writer "line")
      (com.inuoe.jzon:write-value writer (source-line symbol kind source)))))

(defun method-specializer-identity (class)
  (let ((name (class-name class)))
    (if (eq name t)
        "common-lisp:t"
        (let* ((package (symbol-package name))
               (public-p (eq :external (nth-value 1 (find-symbol (symbol-name name) package)))))
          (unless (and public-p
                       (member package *artifact-packages*
                               :key (lambda (spec) (find-package (second spec)))))
            (error "Non-public CLOS method specializer: ~A" name))
          (native-identity name :type)))))

(defun method-signature-text (symbol method)
  (let ((specializers (copy-list (sb-mop:method-specializers method))))
    (with-output-to-string (out)
      (format out "(~A" (spelling symbol))
      (dolist (qualifier (sb-mop:method-qualifiers method))
        (format out " ~A" (signature-text qualifier)))
      (dolist (argument (sb-mop:method-lambda-list method))
        (if specializers
            (let* ((class (pop specializers)) (name (class-name class)))
              (method-specializer-identity class)
              (format out " (~A ~(~A~):~A)" (spelling argument)
                      (package-name (symbol-package name)) (spelling name)))
            (format out " ~A" (signature-text argument))))
      (write-char #\) out))))

(defun write-artifact-methods (writer symbol)
  (com.inuoe.jzon:with-array writer
    (dolist (method (sort (copy-list (sb-mop:generic-function-methods (fdefinition symbol)))
                         #'string< :key (lambda (method) (method-signature-text symbol method))))
      (com.inuoe.jzon:with-object writer
        (com.inuoe.jzon:write-key writer "signature")
        (com.inuoe.jzon:write-value writer (method-signature-text symbol method))
        (com.inuoe.jzon:write-key writer "qualifiers")
        (write-string-array writer (mapcar #'signature-text (sb-mop:method-qualifiers method)))
        (com.inuoe.jzon:write-key writer "specializers")
        (write-string-array writer (mapcar #'method-specializer-identity
                                          (sb-mop:method-specializers method)))))))

(defun write-function-artifact (writer symbol package)
  (let ((kind (function-kind symbol)))
    (com.inuoe.jzon:with-object writer
      (com.inuoe.jzon:write-key writer "id")
      (com.inuoe.jzon:write-value writer (native-identity symbol :function))
      (com.inuoe.jzon:write-key writer "name")
      (com.inuoe.jzon:write-value writer (spelling symbol))
      (com.inuoe.jzon:write-key writer "kind")
      (com.inuoe.jzon:write-value writer "function")
      (com.inuoe.jzon:write-key writer "signature")
      (com.inuoe.jzon:write-value
       writer (signature-text (cons symbol (sb-introspect:function-lambda-list symbol))))
      (com.inuoe.jzon:write-key writer "modifiers")
      (write-string-array writer (if (eq kind :macro) '("macro") '()))
      (com.inuoe.jzon:write-key writer "generic")
      (com.inuoe.jzon:write-value writer
                                  (typep (fdefinition symbol) 'generic-function))
      (when (typep (fdefinition symbol) 'generic-function)
        (com.inuoe.jzon:write-key writer "methods")
        (write-artifact-methods writer symbol))
      (com.inuoe.jzon:write-key writer "documentation")
      (write-artifact-documentation writer symbol 'function package)
      (com.inuoe.jzon:write-key writer "source")
      (write-artifact-source writer symbol kind))))

(defun write-type-artifact (writer symbol package)
  (let* ((condition-p (nth-value 0 (subtypep symbol 'condition)))
         (kind (if condition-p :condition :class))
         (class (find-class symbol)))
    (com.inuoe.jzon:with-object writer
      (com.inuoe.jzon:write-key writer "id")
      (com.inuoe.jzon:write-value writer (native-identity symbol :type))
      (com.inuoe.jzon:write-key writer "name")
      (com.inuoe.jzon:write-value writer (spelling symbol))
      (com.inuoe.jzon:write-key writer "kind")
      (com.inuoe.jzon:write-value writer (if condition-p "exception" "class"))
      (com.inuoe.jzon:write-key writer "modifiers")
      (write-string-array writer '("opaque"))
      (com.inuoe.jzon:write-key writer "supertypes")
      (write-string-array
       writer
       (mapcar (lambda (superclass)
                 (let ((name (class-name superclass)))
                   (if (and (symbolp name) (symbol-package name))
                       (format nil "~A:~A"
                               (string-downcase (package-name (symbol-package name)))
                               (spelling name))
                       (princ-to-string name))))
               (sb-mop:class-direct-superclasses class)))
      (com.inuoe.jzon:write-key writer "documentation")
      (write-artifact-documentation writer class t package)
      (com.inuoe.jzon:write-key writer "source")
      (write-artifact-source writer symbol kind))))

(defun write-package-artifact (writer spec)
  (destructuring-bind (name designator system product source-file) spec
    (let ((package (find-package designator)))
      (com.inuoe.jzon:with-object writer
        (com.inuoe.jzon:write-key writer "name")
        (com.inuoe.jzon:write-value writer name)
        (com.inuoe.jzon:write-key writer "system")
        (com.inuoe.jzon:write-value writer system)
        (com.inuoe.jzon:write-key writer "product")
        (com.inuoe.jzon:write-value writer product)
        (com.inuoe.jzon:write-key writer "documentation")
        (multiple-value-bind (summary body)
            (let* ((text (required-documentation package t))
                   (paragraph (search (format nil "~%~%") text)))
              (values (if paragraph (subseq text 0 paragraph) text)
                      (and paragraph (subseq text (+ paragraph 2)))))
          (com.inuoe.jzon:with-object writer
            (com.inuoe.jzon:write-key writer "summary")
            (com.inuoe.jzon:write-value writer summary)
            (when body
              (com.inuoe.jzon:write-key writer "body")
              (com.inuoe.jzon:write-value writer body))))
        (com.inuoe.jzon:write-key writer "source")
        (com.inuoe.jzon:with-object writer
          (com.inuoe.jzon:write-key writer "file")
          (com.inuoe.jzon:write-value writer source-file)
          (com.inuoe.jzon:write-key writer "line")
          (com.inuoe.jzon:write-value writer 1))
        (com.inuoe.jzon:write-key writer "symbols")
        (com.inuoe.jzon:with-array writer
          (dolist (symbol (public-symbols package))
            (when (fboundp symbol) (write-function-artifact writer symbol package))
            (when (find-class symbol nil) (write-type-artifact writer symbol package))))))))

(defun write-api-artifact (path)
  (let* ((files (artifact-source-files))
         (revision (git-output "rev-parse" "HEAD"))
         (exporter-revision
           (git-output "log" "-1" "--format=%H" "--" "tools/documentation.lisp")))
    (ensure-directories-exist path)
    (uiop:with-output-file (stream path :if-exists :supersede)
      (com.inuoe.jzon:with-writer
          (writer :stream stream :pretty t :max-depth nil)
        (com.inuoe.jzon:with-object writer
          (com.inuoe.jzon:write-key writer "schema")
          (com.inuoe.jzon:write-value writer "libtmux.lisp.api/1")
          (com.inuoe.jzon:write-key writer "port")
          (com.inuoe.jzon:write-value writer "lisp")
          (com.inuoe.jzon:write-key writer "library")
          (com.inuoe.jzon:with-object writer
            (com.inuoe.jzon:write-key writer "version")
            (com.inuoe.jzon:write-value
             writer (asdf:component-version (asdf:find-system "libtmux"))))
          (com.inuoe.jzon:write-key writer "runtime")
          (com.inuoe.jzon:with-object writer
            (com.inuoe.jzon:write-key writer "implementation")
            (com.inuoe.jzon:write-value writer (lisp-implementation-type))
            (com.inuoe.jzon:write-key writer "implementationVersion")
            (com.inuoe.jzon:write-value writer (lisp-implementation-version))
            (com.inuoe.jzon:write-key writer "asdfVersion")
            (com.inuoe.jzon:write-value writer (asdf:asdf-version)))
          (com.inuoe.jzon:write-key writer "source")
          (com.inuoe.jzon:with-object writer
            (com.inuoe.jzon:write-key writer "repository")
            (com.inuoe.jzon:write-value writer "libtmux/libtmux-lisp")
            (com.inuoe.jzon:write-key writer "revision")
            (com.inuoe.jzon:write-value writer revision)
            (com.inuoe.jzon:write-key writer "dirty")
            (com.inuoe.jzon:write-value writer (tracked-dirty-p files))
            (com.inuoe.jzon:write-key writer "files")
            (com.inuoe.jzon:with-array writer
              (dolist (file files)
                (com.inuoe.jzon:with-object writer
                  (com.inuoe.jzon:write-key writer "path")
                  (com.inuoe.jzon:write-value writer file)
                  (com.inuoe.jzon:write-key writer "sha256")
                  (com.inuoe.jzon:write-value writer (sha256-file file))))))
          (com.inuoe.jzon:write-key writer "exporter")
          (com.inuoe.jzon:with-object writer
            (com.inuoe.jzon:write-key writer "name")
            (com.inuoe.jzon:write-value writer "libtmux.documentation")
            (com.inuoe.jzon:write-key writer "version")
            (com.inuoe.jzon:write-value writer 1)
            (com.inuoe.jzon:write-key writer "revision")
            (com.inuoe.jzon:write-value writer exporter-revision)
            (com.inuoe.jzon:write-key writer "dirty")
            (com.inuoe.jzon:write-value
             writer (tracked-dirty-p '("tools/documentation.lisp"))))
          (com.inuoe.jzon:write-key writer "packages")
          (com.inuoe.jzon:with-array writer
            (dolist (spec *artifact-packages*)
              (write-package-artifact writer spec)))))))
  (format t "Native API artifact: PASS (~A)~%" path))

(defun type-reference (class)
  (let ((symbol (class-name class)))
    (if (eq (symbol-package symbol) (find-package :libtmux))
        (format nil "[~A](#~A-type)" (spelling symbol) (spelling symbol))
        (format nil "`~A`" (spelling symbol)))))

(defun render-api ()
  (let ((*package* (find-package :libtmux)) (*print-case* :downcase)
        (*print-pretty* nil) (*print-circle* t))
    (with-output-to-string (out)
      (format out "# Public API~%~%Generated from live package documentation and function signatures by~%`mise run docs`. Edit source docstrings; `mise run check` detects drift.~%~%[Guide index](index.md) · [Field reference](fields.md) · [Tutorial](tutorial.md)~%~%")
      (format out "~A~%~%" (required-documentation (find-package :libtmux) t))
      (format out "## Functions and macros~%~%")
      (let* ((functions (remove-if-not #'fboundp (public-symbols)))
             (sources (mapcar (lambda (symbol)
                                ;; These selectors share a file with capture and rename.
                                (if (member symbol '(libtmux:select-pane libtmux:select-window))
                                    "selection"
                                    (pathname-name (definition-path symbol (function-kind symbol)))))
                              functions))
             (indexed nil))
        (dolist (group *index-groups*)
          (format out "**~A**~%~%" (first group))
          (loop for symbol in functions for source in sources
                when (member source (rest group) :test #'string=)
                  do (push symbol indexed)
                     (format out "[~A](#~A-function)~%" (spelling symbol) (spelling symbol)))
          (terpri out))
        (dolist (symbol (public-symbols))
          (when (and (fboundp symbol) (not (member symbol indexed)))
            (error "Public function lacks an API index group: ~A" symbol))))
      (dolist (symbol (public-symbols))
        (when (fboundp symbol)
          (multiple-value-bind (documentation related)
              (documentation-parts symbol 'function)
            (format out "<a id=\"~A-function\"></a>~%~%### ~A~%~%`~A`~%~%~A~%~%"
                    (spelling symbol) (spelling symbol)
                    (signature-text (cons symbol (sb-introspect:function-lambda-list symbol)))
                    documentation)
            (when related (format out "~A~%~%" related))
            (format out "~A~%~%" (source-link symbol (function-kind symbol))))
          (when (typep (fdefinition symbol) 'generic-function)
            (format out "Applicable first argument types: ~{~A~^, ~}.~%~%"
                    (sort (remove-duplicates
                           (loop for method in (sb-mop:generic-function-methods (fdefinition symbol))
                                 collect (type-reference (first (sb-mop:method-specializers method))))
                           :test #'string=) #'string<)))))
      (format out "## Classes and conditions~%~%These types are acquired or signalled by the library; their slots are private.~%~%")
      (dolist (symbol (public-symbols))
        (let ((class (find-class symbol nil)))
          (when class
            (format out "<a id=\"~A-type\"></a>~%~%### ~A~%~%~A~%~%~A~%~%"
                    (spelling symbol) (spelling symbol)
                    (required-documentation class t) (source-link symbol (if (subtypep symbol 'condition) :condition :class)))
            (format out "Direct supertypes: ~{~A~^, ~}.~%~%"
                    (mapcar #'type-reference (sb-mop:class-direct-superclasses class)))))))))

(defun render-fields ()
  (with-output-to-string (out)
    (format out "# Captured fields~%~%Generated from registry version ~D by `mise run docs`.~%~%Use `field-value` with a captured entity and one keyword below. It returns~%value and presence as two values. Present false is `nil, t`; absence is~%`nil, nil`. Text and relation containers are copied. All access is local.~%An unknown field or unloaded relation signals `field-unavailable`.~%~%[Graph and ownership](captures.md) · [API](api.md#field-value-function)~%~%"
            internal::+registry-version+)
    (dolist (model '(:session :window :pane :window-link :client))
      (format out "## ~A~%~%| Field | Type | Presence / relation |~%| --- | --- | --- |~%" model)
      (dolist (field (internal::model-fields model))
        (format out "| `~S` | ~A | ~A |~%"
                (internal::field-spec-key field)
                (case (internal::field-spec-kind field)
                  (:text "String") (:boolean "Boolean")
                  (:integer (format nil "Integer ~D…~D" (internal::field-spec-minimum field)
                                    (internal::field-spec-maximum field)))
                  (:relation (format nil "~A ~A" (internal::field-spec-cardinality field)
                                     (internal::field-spec-target field))))
                (if (eq :relation (internal::field-spec-kind field)) "Captured target(s)"
                    (if (internal::field-spec-optional field) "Optional" "Present"))))
      (terpri out))
    (format out "`:CLIENT` is the attached-client model, not the connection client.~%Optional integer `:pane/pid` treats tmux's zero as absence. Optional text~%treats an empty wire value as absence. Session creation time may be absent.~%Names and titles retain present empty strings. See [capture semantics](captures.md).~%")))

(defun render-query-api ()
  (let ((*package* (find-package :libtmux.query)) (*print-case* :downcase)
        (*print-pretty* nil) (*print-circle* t))
    (with-output-to-string (out)
      (format out "# Native query API~%~%Generated from live package documentation, signatures and operator metadata by~%`mise run docs`. Edit source docstrings and the operator registry; `mise run~%check` detects drift.~%~%[Query guide](queries.md) · [Captured fields](fields.md) · [Core API](api.md)~%~%")
      (format out "~A~%~%" (required-documentation (find-package :libtmux.query) t))
      (format out "## Functions~%~%")
      (dolist (symbol (public-symbols :libtmux.query))
        (when (fboundp symbol)
          (multiple-value-bind (documentation related)
              (documentation-parts symbol 'function :libtmux.query)
            (format out "<a id=\"~A-function\"></a>~%~%### ~A~%~%`~A`~%~%~A~%~%"
                    (spelling symbol) (spelling symbol)
                    (signature-text (cons symbol (sb-introspect:function-lambda-list symbol)))
                    documentation)
            (when related (format out "~A~%~%" related))
            (format out "~A~%~%" (source-link symbol (function-kind symbol))))))
      (format out "## Classes and conditions~%~%These objects retain owned, bounded query state; their slots are private.~%~%")
      (dolist (symbol (public-symbols :libtmux.query))
        (let ((class (find-class symbol nil)))
          (when class
            (format out "<a id=\"~A-type\"></a>~%~%### ~A~%~%~A~%~%~A~%~%Direct supertypes: ~{`~A`~^, ~}.~%~%"
                    (spelling symbol) (spelling symbol)
                    (required-documentation class t)
                    (source-link symbol (if (subtypep symbol 'condition) :condition :class))
                    (mapcar (lambda (superclass)
                              (string-downcase (symbol-name (class-name superclass))))
                            (sb-mop:class-direct-superclasses class))))))
      (format out "## Operators~%~%Scalar and relation rows are implemented by `libtmux/query`. Regex operators~%become available when the optional `libtmux/regex` system is loaded.~%~%| Operator | Arity | Field kinds | Stage | Meaning |~%| --- | ---: | --- | --- | --- |~%")
      (loop for spec across libtmux.query::*operator-specs*
            do (format out "| `~S` | ~A | ~{`~A`~^, ~} | `~A` | ~A |~%"
                       (libtmux.query::operator-spec-key spec)
                       (let ((arity (libtmux.query::operator-spec-arity spec)))
                         (if (eq arity :variadic) "variadic" arity))
                       (libtmux.query::operator-spec-field-kinds spec)
                       (libtmux.query::operator-spec-stage spec)
                       (libtmux.query::operator-spec-documentation spec))))))

(defun render-json-api ()
  (let ((*package* (find-package :libtmux.json)) (*print-case* :downcase)
        (*print-pretty* nil) (*print-circle* t))
    (with-output-to-string (out)
      (format out "# Query JSON API~%~%Generated from live package documentation and signatures by `mise run docs`.~%Edit source docstrings; `mise run check` detects drift.~%~%[Interchange guide](query-interchange.md) · [Query guide](queries.md)~%~%")
      (format out "~A~%~%" (required-documentation (find-package :libtmux.json) t))
      (format out "## Functions~%~%")
      (dolist (symbol (public-symbols :libtmux.json))
        (when (fboundp symbol)
          (multiple-value-bind (documentation related)
              (documentation-parts symbol 'function :libtmux.json)
            (format out "<a id=\"~A-function\"></a>~%~%### ~A~%~%`~A`~%~%~A~%~%"
                    (spelling symbol) (spelling symbol)
                    (signature-text (cons symbol (sb-introspect:function-lambda-list symbol)))
                    documentation)
            (when related (format out "~A~%~%" related))
            (format out "~A~%~%" (source-link symbol (function-kind symbol))))))
      (format out "## Conditions~%~%These types retain bounded document diagnostics; their slots are private.~%~%")
      (dolist (symbol (public-symbols :libtmux.json))
        (let ((class (find-class symbol nil)))
          (when class
            (format out "<a id=\"~A-type\"></a>~%~%### ~A~%~%~A~%~%~A~%~%Direct supertypes: ~{`~A`~^, ~}.~%~%"
                    (spelling symbol) (spelling symbol)
                    (required-documentation class t)
                    (source-link symbol (if (subtypep symbol 'condition) :condition :class))
                    (mapcar (lambda (superclass)
                              (string-downcase (symbol-name (class-name superclass))))
                            (sb-mop:class-direct-superclasses class)))))))))

(defun render-workspace-api ()
  (let ((*package* (find-package :libtmux.workspace)) (*print-case* :downcase)
        (*print-pretty* nil) (*print-circle* t))
    (with-output-to-string (out)
      (format out "# Workspace API~%~%Generated from live package documentation and signatures by `mise run docs`.~%Edit source docstrings; `mise run check` detects drift.~%~%[Workspace guide](workspaces.md) · [Core API](api.md) · [Transport](transport.md)~%~%")
      (format out "~A~%~%" (required-documentation (find-package :libtmux.workspace) t))
      (format out "## Functions~%~%")
      (dolist (symbol (public-symbols :libtmux.workspace))
        (when (fboundp symbol)
          (multiple-value-bind (documentation related)
              (documentation-parts symbol 'function :libtmux.workspace)
            (format out "<a id=\"~A-function\"></a>~%~%### ~A~%~%`~A`~%~%~A~%~%"
                    (spelling symbol) (spelling symbol)
                    (signature-text (cons symbol (sb-introspect:function-lambda-list symbol)))
                    documentation)
            (when related (format out "~A~%~%" related))
            (format out "~A~%~%" (source-link symbol (function-kind symbol))))))
      (format out "## Classes and conditions~%~%These objects retain owned configuration, plans, results, or bounded diagnostics.~%~%")
      (dolist (symbol (public-symbols :libtmux.workspace))
        (let ((class (find-class symbol nil)))
          (when class
            (format out "<a id=\"~A-type\"></a>~%~%### ~A~%~%~A~%~%~A~%~%Direct supertypes: ~{`~A`~^, ~}.~%~%"
                    (spelling symbol) (spelling symbol)
                    (required-documentation class t)
                    (source-link symbol (if (subtypep symbol 'condition) :condition :class))
                    (mapcar (lambda (superclass)
                              (string-downcase (symbol-name (class-name superclass))))
                            (sb-mop:class-direct-superclasses class))))))
      (let* ((symbol (find-symbol "MAIN" :libtmux.workspace.cli))
             (*package* (find-package :libtmux.workspace.cli)))
        (format out "## Command-line adapter~%~%The separate `libtmux/workspace/cli` system exports one testable entry point. See [read-workspace](#read-workspace-function), [plan-workspace](#plan-workspace-function), and [apply-workspace](#apply-workspace-function).~%~%")
        (multiple-value-bind (documentation related)
            (documentation-parts symbol 'function :libtmux.workspace)
          (format out "<a id=\"main-function\"></a>~%~%### main~%~%`~A`~%~%~A~%~%"
                  (signature-text (cons symbol (sb-introspect:function-lambda-list symbol)))
                  documentation)
          (when related (format out "~A~%~%" related))
          (format out "~A~%~%" (source-link symbol (function-kind symbol))))))))

(defun render-modules ()
  (with-output-to-string (out)
    (format out "# Source modules~%~%Generated from ASDF component descriptions by `mise run docs`.~%These files implement the core `libtmux` system; their internal package is private.~%~%[Public API](api.md) · [Architecture and boundaries](captures.md)~%~%| Source | Responsibility |~%| --- | --- |~%")
    (dolist (component (asdf:component-children (asdf:find-system "libtmux")))
      (format out "| [~A](../~A) | ~A |~%" (asdf:component-name component)
              (enough-namestring (asdf:component-pathname component) (uiop:getcwd))
              (or (asdf/component:component-description component)
                  (error "Missing module description: ~A" component))))
    (format out "~%## Separate systems~%~%| System | Source | Responsibility |~%| --- | --- | --- |~%")
    (dolist (system-name '("libtmux/query" "libtmux/regex" "libtmux/json"
                           "libtmux/workspace" "libtmux/workspace/cli"))
      (let ((system (asdf:find-system system-name)))
        (dolist (component (asdf:component-children system))
          (format out "| `~A` | [~A](../~A) | ~A |~%" system-name
                  (asdf:component-name component)
                  (enough-namestring (asdf:component-pathname component) (uiop:getcwd))
                  (or (asdf/component:component-description component)
                      (error "Missing module description: ~A" component))))))))

(defun synchronize (path text write-p)
  (let ((text (concatenate 'string (string-right-trim '(#\Newline) text)
                           (string #\Newline))))
    (if write-p (uiop:with-output-file (out path :if-exists :supersede)
                  (write-string text out))
        (unless (and (probe-file path) (string= text (uiop:read-file-string path)))
          (error "Stale documentation: ~A; run mise run docs" path)))))

(let* ((arguments (uiop:command-line-arguments))
       (write-p (equal '("write") arguments))
       (artifact-p (and arguments (string= "artifact" (first arguments))))
       (artifact-path (or (second arguments) "docs/_build/api.json")))
  (unless (or (null arguments) write-p artifact-p)
    (error "Usage: tools/documentation.lisp [write|artifact [PATH]]"))
  (synchronize "docs/api.md" (render-api) write-p)
  (synchronize "docs/query-api.md" (render-query-api) write-p)
  (synchronize "docs/json-api.md" (render-json-api) write-p)
  (synchronize "docs/workspace-api.md" (render-workspace-api) write-p)
  (synchronize "docs/fields.md" (render-fields) write-p)
  (synchronize "docs/modules.md" (render-modules) write-p)
  (when artifact-p (write-api-artifact artifact-path))
  (format t "Public docstrings, API signatures, fields and module documentation: PASS~%"))
