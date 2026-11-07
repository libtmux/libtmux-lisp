(require :asdf)
(require :sb-introspect)
(asdf:load-asd (truename "libtmux.asd"))
(asdf:load-system "libtmux")
(asdf:load-system "libtmux/query")
(asdf:load-system "libtmux/regex")
(asdf:load-system "libtmux/json")

(defpackage #:libtmux.documentation
  (:use #:cl)
  (:local-nicknames (#:internal #:libtmux.internal)))
(in-package #:libtmux.documentation)

(defun public-symbols (&optional (package :libtmux))
  (sort (loop for symbol being the external-symbols of (find-package package)
              collect symbol) #'string< :key #'symbol-name))

(defun spelling (symbol)
  (string-downcase (symbol-name symbol)))

(defun symbol-token-character-p (character)
  (or (alphanumericp character)
      (find character "-+*/<>=?!%&_")))

(defun symbol-mentioned-p (symbol text)
  "Return true when TEXT names SYMBOL as a complete uppercase Lisp token."
  (let ((name (symbol-name symbol)))
    (loop with start = 0
          for position = (search name text :start2 start)
          while position
          for end = (+ position (length name))
          when (and (or (zerop position)
                        (not (symbol-token-character-p (char text (1- position)))))
                    (or (= end (length text))
                        (not (symbol-token-character-p (char text end)))))
            return t
          do (setf start (1+ position))
          finally (return nil))))

(defun api-anchor (symbol)
  (cond ((fboundp symbol) (format nil "#~A-function" (spelling symbol)))
        ((find-class symbol nil) (format nil "#~A-type" (spelling symbol)))))

(defun see-also (symbol references &optional (package (symbol-package symbol)))
  "Build API-browser links from an explicit See also docstring line."
  (let ((references
          (loop for candidate in (public-symbols package)
                for anchor = (api-anchor candidate)
                when (and anchor (not (eq candidate symbol))
                          (symbol-mentioned-p candidate references))
                  collect (format nil "[~A](~A)" (spelling candidate) anchor))))
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
    ("Select, arrange and link targets" "geometry" "selection" "placement")
    ("Rename, capture, send input and manage pane processes"
     "operations" "terminal-operations" "process-operations")
    ("Read and write buffers and files" "buffers")
    ("Configure options, hooks and environment" "configuration-operations")
    ("Inspect failure evidence" "conditions")))

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

(defun render-modules ()
  (with-output-to-string (out)
    (format out "# Source modules~%~%Generated from ASDF component descriptions by `mise run docs`.~%These files implement the core `libtmux` system; their internal package is private.~%~%[Public API](api.md) · [Architecture and boundaries](captures.md)~%~%| Source | Responsibility |~%| --- | --- |~%")
    (dolist (component (asdf:component-children (asdf:find-system "libtmux")))
      (format out "| [~A](../~A) | ~A |~%" (asdf:component-name component)
              (enough-namestring (asdf:component-pathname component) (uiop:getcwd))
              (or (asdf/component:component-description component)
                  (error "Missing module description: ~A" component))))
    (format out "~%## Separate systems~%~%| System | Source | Responsibility |~%| --- | --- | --- |~%")
    (dolist (system-name '("libtmux/query" "libtmux/regex" "libtmux/json"))
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

(let ((write-p (equal '("write") (uiop:command-line-arguments))))
  (synchronize "docs/api.md" (render-api) write-p)
  (synchronize "docs/query-api.md" (render-query-api) write-p)
  (synchronize "docs/json-api.md" (render-json-api) write-p)
  (synchronize "docs/fields.md" (render-fields) write-p)
  (synchronize "docs/modules.md" (render-modules) write-p)
  (format t "Public docstrings, API signatures, fields and module documentation: PASS~%"))
