(defpackage #:libtmux.regex
  (:use #:cl)
  (:documentation "Optional CL-PPCRE operators for libtmux.query.
Loading this package enables :REGEX-SEARCH and :REGEX-FULL-MATCH. It performs
no tmux I/O. Scanner execution is ordinary local CL-PPCRE work and is not
interruptible through the query visit budget."))

(in-package #:libtmux.regex)

(defparameter +scanner-options+
  '(:case-insensitive-mode :multi-line-mode :single-line-mode :extended-mode))

(defun invalid-regex (model form field expected received message &optional cause)
  (error 'libtmux.query:invalid-filter
         :model model
         :path (coerce (reverse libtmux.query::*compile-path*) 'simple-vector)
         :operator (first form)
         :field field
         :expected expected
         :received received
         :cause cause
         :message message))

(defun proper-list-length (value)
  (if (listp value)
      (handler-case (values (length value) t)
        (type-error () (values nil nil)))
      (values nil nil)))

(defun scanner-options-without-extended-mode (options)
  (loop for (key value) on options by #'cddr
        unless (eq key :extended-mode)
          append (list key value)))

(defun prepared-scanner (operator pattern options)
  (let ((cl-ppcre:*allow-quoting* nil)
        (cl-ppcre:*allow-named-registers* nil))
    (if (eq operator :regex-search)
        (apply #'cl-ppcre:create-scanner pattern options)
        (let* ((extended-mode (getf options :extended-mode))
               (parse-source
                 (if extended-mode
                     (concatenate 'string "(?x)" pattern)
                     pattern))
               (parse-tree (cl-ppcre:parse-string parse-source))
               (anchored-tree
                 `(:sequence :modeless-start-anchor
                   (:group ,parse-tree)
                   :modeless-end-anchor-no-newline)))
          (apply #'cl-ppcre:create-scanner anchored-tree
                 (scanner-options-without-extended-mode options))))))

(defun normalized-regex-spec (model form field)
  (let ((source (third form)))
    (multiple-value-bind (length proper-p) (proper-list-length source)
      (unless (and proper-p (>= length 2) (evenp length))
        (invalid-regex model form field
                       '(:cl-ppcre pattern &key scanner-options)
                       (type-of source)
                       "A regex operand must be a proper :CL-PPCRE option list")))
    (unless (eq :cl-ppcre (first source))
      (invalid-regex model form field :cl-ppcre
                     (libtmux.query::safe-designator-summary (first source))
                     "The regex engine must be :CL-PPCRE"))
    (unless (stringp (second source))
      (invalid-regex model form field :string (type-of (second source))
                     "The CL-PPCRE pattern must be a string"))
    (let ((seen (make-hash-table :test 'eq))
          (options nil))
      (loop for (key value) on (cddr source) by #'cddr
            do (unless (member key +scanner-options+)
                 (invalid-regex model form field +scanner-options+
                                (libtmux.query::safe-designator-summary key)
                                "The CL-PPCRE scanner option is not supported"))
               (when (gethash key seen)
                 (invalid-regex model form field :unique-scanner-options key
                                "A CL-PPCRE scanner option occurs more than once"))
               (unless (or (eq value t) (null value))
                 (invalid-regex model form field :boolean (type-of value)
                                "CL-PPCRE scanner options must be T or NIL"))
               (setf (gethash key seen) t)
               (push key options)
               (push value options))
      (values (second source) (nreverse options) source))))

(defun compile-regex-node (operator model form requirements seen)
  (let* ((field (libtmux.query::scalar-field
                 model form operator requirements seen))
         (key (libtmux.internal::field-spec-key field)))
    (multiple-value-bind (pattern options retained-spec)
        (normalized-regex-spec model form key)
      (let ((scanner
              (handler-case
                  (prepared-scanner operator pattern options)
                (error (cause)
                  (invalid-regex model form key :valid-cl-ppcre-pattern
                                 :invalid-pattern
                                 "CL-PPCRE rejected the regex pattern"
                                 cause)))))
        (libtmux.query::make-query-node
         operator
         (lambda (entity context)
           (declare (ignore context))
           (multiple-value-bind (value present-p)
               (libtmux.internal::resolved-field-value entity field)
             (and present-p
                  (not (null (cl-ppcre:scan scanner value))))))
         :field key :operand retained-spec)))))

(defmethod libtmux.query::compile-optional-node
    ((operator (eql :regex-search)) model form requirements seen
     relation-requirements relation-seen limits)
  (declare (ignore relation-requirements relation-seen limits))
  (compile-regex-node operator model form requirements seen))

(defmethod libtmux.query::compile-optional-node
    ((operator (eql :regex-full-match)) model form requirements seen
     relation-requirements relation-seen limits)
  (declare (ignore relation-requirements relation-seen limits))
  (compile-regex-node operator model form requirements seen))
