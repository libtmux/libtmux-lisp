(require :asdf)
(require :sb-introspect)
(asdf:load-asd (truename "libtmux.asd"))
(asdf:load-system "libtmux")

(defpackage #:libtmux.documentation
  (:use #:cl)
  (:local-nicknames (#:internal #:libtmux.internal)))
(in-package #:libtmux.documentation)

(defun public-symbols ()
  (sort (loop for symbol being the external-symbols of (find-package :libtmux)
              collect symbol) #'string< :key #'symbol-name))

(defun spelling (symbol)
  (string-downcase (symbol-name symbol)))

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
          (format out "<a id=\"~A-function\"></a>~%~%### ~A~%~%`~A`~%~%~A~%~%~A~%~%"
                  (spelling symbol) (spelling symbol)
                  (signature-text (cons symbol (sb-introspect:function-lambda-list symbol)))
                  (required-documentation symbol 'function)
                  (source-link symbol (function-kind symbol)))
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

(defun render-modules ()
  (with-output-to-string (out)
    (format out "# Source modules~%~%Generated from ASDF component descriptions by `mise run docs`.~%These files implement the core `libtmux` system; their internal package is private.~%~%[Public API](api.md) · [Architecture and boundaries](captures.md)~%~%| Source | Responsibility |~%| --- | --- |~%")
    (dolist (component (asdf:component-children (asdf:find-system "libtmux")))
      (format out "| [~A](../~A) | ~A |~%" (asdf:component-name component)
              (enough-namestring (asdf:component-pathname component) (uiop:getcwd))
              (or (asdf/component:component-description component)
                  (error "Missing module description: ~A" component))))))

(defun synchronize (path text write-p)
  (let ((text (concatenate 'string (string-right-trim '(#\Newline) text)
                           (string #\Newline))))
    (if write-p (uiop:with-output-file (out path :if-exists :supersede)
                  (write-string text out))
        (unless (and (probe-file path) (string= text (uiop:read-file-string path)))
          (error "Stale documentation: ~A; run mise run docs" path)))))

(let ((write-p (equal '("write") (uiop:command-line-arguments))))
  (synchronize "docs/api.md" (render-api) write-p)
  (synchronize "docs/fields.md" (render-fields) write-p)
  (synchronize "docs/modules.md" (render-modules) write-p)
  (format t "Public docstrings, API signatures, fields and module documentation: PASS~%"))
