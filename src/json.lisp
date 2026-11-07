(defpackage #:libtmux.json
  (:use #:cl)
  (:documentation "Bounded JSON interchange for native libtmux query filters.
READ-FILTER accepts a complete JSON string in schema libtmux.lisp.filter/1.
It resolves only registered names, rejects duplicate or unknown members, and
never evaluates input as Lisp code. WRITE-FILTER serializes only compiled
declarative filters; native function predicates are not query documents.")
  (:export
   #:read-filter #:write-filter
   #:invalid-filter-document #:filter-document-limit-exceeded
   #:document-path #:document-limit))

(in-package #:libtmux.json)

(defgeneric document-path (condition)
  (:documentation "Return a fresh vector locating a filter-document error."))

(defgeneric document-limit (condition)
  (:documentation "Return the exhausted document limit name, or NIL."))

(define-condition invalid-filter-document (libtmux:libtmux-error)
  ((path :initarg :path :initform #())
   (limit :initarg :limit :initform nil)
   (received :initarg :received :initform nil))
  (:documentation "A filter document is malformed, unknown, or semantically invalid."))

(define-condition filter-document-limit-exceeded (invalid-filter-document) ()
  (:documentation "A filter document exceeds a configured parsing or query-data limit."))

(defmethod document-path ((condition invalid-filter-document))
  (libtmux.internal::owned-data (slot-value condition 'path)))

(defmethod document-limit ((condition invalid-filter-document))
  (slot-value condition 'limit))

(defparameter *schema* "libtmux.lisp.filter/1")
(defconstant +default-max-input-bytes+ 1048576)
(defconstant +default-max-depth+ 64)
(defconstant +default-max-nodes+ 10000)
(defconstant +default-max-string-length+ 65536)
(defconstant +default-max-membership+ 1000)
(defconstant +default-max-integer-digits+ 128)

(defparameter +root-members+
  '("schema" "model" "registryVersion" "expression"))

(defparameter +model-names+
  '(("session" . :session)
    ("window" . :window)
    ("pane" . :pane)
    ("window-link" . :window-link)
    ("client" . :client)))

(defparameter +operator-names+
  '(("=" . :=) ("<" . :<) ("<=" . :<=) (">" . :>) (">=" . :>=)
    ("in" . :in) ("contains" . :contains) ("starts-with" . :starts-with)
    ("and" . :and) ("or" . :or) ("not" . :not)
    ("present" . :present) ("missing" . :missing)
    ("any" . :any) ("all" . :all) ("none" . :none) ("is" . :is)
    ("regex-search" . :regex-search)
    ("regex-full-match" . :regex-full-match)))

(defparameter +regex-option-names+
  '(("caseInsensitiveMode" . :case-insensitive-mode)
    ("multiLineMode" . :multi-line-mode)
    ("singleLineMode" . :single-line-mode)
    ("extendedMode" . :extended-mode)))

(defstruct (json-object (:constructor make-json-object (entries)))
  entries)

(defun safe-received (value)
  (cond ((and (stringp value) (<= (length value) 80)) (copy-seq value))
        ((and (keywordp value) (<= (length (symbol-name value)) 80)) value)
        (t (type-of value))))

(defun fail-document (message &key path cause limit received)
  (error (if limit 'filter-document-limit-exceeded 'invalid-filter-document)
         :path (coerce (reverse path) 'simple-vector)
         :limit limit
         :cause cause
         :message message
         :outcome nil
         :client nil
         :received (safe-received received)))

(defun checked-limit (value name minimum)
  (unless (and (integerp value) (>= value minimum))
    (fail-document (format nil "~S must be an integer no smaller than ~D"
                           name minimum)
                   :received value))
  value)

(defun bounded-utf-8-size (source limit)
  (let ((size 0))
    (loop for character across source
          for code = (char-code character)
          do (incf size (cond ((<= code #x7f) 1)
                              ((<= code #x7ff) 2)
                              ((<= code #xffff) 3)
                              (t 4)))
             (when (> size limit)
               (fail-document
                (format nil "Filter document exceeds ~D UTF-8 bytes" limit)
                :limit :max-input-bytes :received size)))
    size))

(defun json-delimiter-p (character)
  (member character
          '(#\Space #\Tab #\Return #\Linefeed #\, #\] #\} #\{ #\[)
          :test #'char=))

(defun validate-numeric-token-bounds (source limit)
  (let ((index 0)
        (length (length source))
        (in-string nil)
        (escaped nil))
    (loop while (< index length)
          for character = (char source index)
          do (cond
               (in-string
                (cond (escaped (setf escaped nil))
                      ((char= character #\\) (setf escaped t))
                      ((char= character #\") (setf in-string nil)))
                (incf index))
               ((char= character #\")
                (setf in-string t)
                (incf index))
               ((or (digit-char-p character)
                    (and (char= character #\-)
                         (< (1+ index) length)
                         (digit-char-p (char source (1+ index)))))
                (let ((cursor index))
                  (loop while (and (< cursor length)
                                   (not (json-delimiter-p (char source cursor))))
                        do (incf cursor))
                  (let* ((first-digit
                           (if (char= (char source index) #\-)
                               (1+ index)
                               index))
                         (digits (- cursor first-digit)))
                    (unless (loop for position from first-digit below cursor
                                  always (digit-char-p (char source position)))
                      (fail-document
                       "Filter documents accept integer JSON numbers only"
                       :received (subseq source index cursor)))
                    (when (> digits limit)
                      (fail-document
                       (format nil "A numeric token exceeds ~D decimal digits" limit)
                       :limit :max-integer-digits :received digits))
                    (setf index cursor))))
               (t (incf index))))))

(defun parse-bounded-json (source max-depth max-nodes max-string-length)
  (let ((nodes 0))
    (labels ((checkpoint (path)
               (when (> (incf nodes) max-nodes)
                 (fail-document
                  (format nil "Filter document exceeds ~D JSON nodes" max-nodes)
                  :path path :limit :max-nodes :received nodes)))
             (read-event (parser event value depth path)
               (checkpoint path)
               (case event
                 (:value
                  (if (and (floatp value) (zerop value)) 0 value))
                 (:begin-array
                  (when (> depth max-depth)
                    (fail-document
                     (format nil "Filter document exceeds nesting depth ~D" max-depth)
                     :path path :limit :max-depth :received depth))
                  (let ((items (make-array 4 :adjustable t :fill-pointer 0))
                        (index 0))
                    (loop
                      (multiple-value-bind (next-event next-value)
                          (com.inuoe.jzon:parse-next parser)
                        (cond ((eq next-event :end-array) (return))
                              ((null next-event)
                               (fail-document "Unexpected end of JSON array" :path path))
                              (t
                               (vector-push-extend
                                (read-event parser next-event next-value (1+ depth)
                                            (cons index path))
                                items)
                               (incf index)))))
                    (coerce items 'simple-vector)))
                 (:begin-object
                  (when (> depth max-depth)
                    (fail-document
                     (format nil "Filter document exceeds nesting depth ~D" max-depth)
                     :path path :limit :max-depth :received depth))
                  (let ((entries nil)
                        (seen (make-hash-table :test 'equal)))
                    (loop
                      (multiple-value-bind (next-event key)
                          (com.inuoe.jzon:parse-next parser)
                        (cond ((eq next-event :end-object) (return))
                              ((null next-event)
                               (fail-document "Unexpected end of JSON object" :path path))
                              ((not (eq next-event :object-key))
                               (fail-document "Expected a JSON object member" :path path
                                              :received next-event))
                              ((gethash key seen)
                               (fail-document "A JSON object member occurs more than once"
                                              :path (cons key path) :received key))
                              (t
                               (setf (gethash key seen) t)
                               (multiple-value-bind (value-event member-value)
                                   (com.inuoe.jzon:parse-next parser)
                                 (when (null value-event)
                                   (fail-document "A JSON object member has no value"
                                                  :path (cons key path)))
                                 (push (cons key
                                             (read-event parser value-event member-value
                                                         (1+ depth) (cons key path)))
                                       entries))))))
                    (make-json-object (nreverse entries))))
                 ((:end-array :end-object :object-key)
                  (fail-document "Unexpected JSON structural token" :path path
                                 :received event))
                 (otherwise
                  (fail-document "Unexpected end of JSON input" :path path))))
             (parse-root ()
               (com.inuoe.jzon:with-parser
                   (parser source :max-string-length max-string-length :key-fn nil)
                 (multiple-value-bind (event value)
                     (com.inuoe.jzon:parse-next parser)
                   (when (null event)
                     (fail-document "A filter document must contain one JSON value"))
                   (let ((result (read-event parser event value 1 nil)))
                     (multiple-value-bind (extra-event extra-value)
                         (com.inuoe.jzon:parse-next parser)
                       (declare (ignore extra-value))
                       (when extra-event
                         (fail-document "A filter document must contain one JSON value")))
                     result)))))
      (handler-case (parse-root)
        (com.inuoe.jzon:json-parse-limit-error (cause)
          (fail-document "Jzon exhausted the configured string bound"
                         :limit :max-string-length :cause cause))
        (com.inuoe.jzon:json-error (cause)
          (fail-document "Jzon rejected the filter document" :cause cause))))))

(defun object-member (object name)
  (let ((entry (assoc name (json-object-entries object) :test #'string=)))
    (if entry (values (cdr entry) t) (values nil nil))))

(defun required-object-member (object name path)
  (multiple-value-bind (value present-p) (object-member object name)
    (unless present-p
      (fail-document "A required filter-document member is missing"
                     :path (cons name path) :received name))
    value))

(defun closed-object (object allowed path)
  (unless (json-object-p object)
    (fail-document "Expected a JSON object" :path path :received object))
  (loop for entry in (json-object-entries object)
        for name = (car entry)
        unless (member name allowed :test #'string=)
          do (fail-document "A JSON object member is not allowed"
                            :path (cons name path) :received name))
  object)

(defun external-name (name table description path)
  (unless (stringp name)
    (fail-document (format nil "~A must be a JSON string" description)
                   :path path :received name))
  (let ((entry (assoc name table :test #'string=)))
    (unless entry
      (fail-document (format nil "Unknown ~A" description)
                     :path path :received name))
    (cdr entry)))

(defun model-name (model)
  (car (rassoc model +model-names+ :test #'eq)))

(defun operator-name (operator)
  (car (rassoc operator +operator-names+ :test #'eq)))

(defun field-name (key)
  (string-downcase (symbol-name key)))

(defun registered-wire-field (model name path)
  (unless (stringp name)
    (fail-document "A query field name must be a JSON string"
                   :path path :received name))
  (or (loop for field in (libtmux.internal::model-fields model)
            when (string= name (field-name (libtmux.internal::field-spec-key field)))
              return field)
      (fail-document "The query field is not registered for this model"
                     :path path :received name)))

(defun scalar-json-value (value path)
  (cond ((eq value 'null)
         (fail-document "JSON null is not a scalar query operand"
                        :path path :received :null))
        ((or (stringp value) (integerp value) (eq value t) (null value)) value)
        (t (fail-document "A scalar query operand has an unsupported JSON type"
                          :path path :received value))))

(defun json-array-p (value)
  (and (vectorp value) (not (stringp value))))

(defun regex-wire-spec (value path)
  (closed-object value '("engine" "pattern" "options") path)
  (let ((engine (required-object-member value "engine" path))
        (pattern (required-object-member value "pattern" path))
        (options (required-object-member value "options" path)))
    (unless (and (stringp engine) (string= engine "cl-ppcre"))
      (fail-document "The regex engine must be cl-ppcre"
                     :path (cons "engine" path) :received engine))
    (unless (stringp pattern)
      (fail-document "The regex pattern must be a JSON string"
                     :path (cons "pattern" path) :received pattern))
    (closed-object options (mapcar #'car +regex-option-names+)
                   (cons "options" path))
    (let ((native (list :cl-ppcre (copy-seq pattern))))
      (loop for (name . option) in (json-object-entries options)
            for native-option = (external-name name +regex-option-names+
                                               "regex option"
                                               (cons name (cons "options" path)))
            do (unless (or (eq option t) (null option))
                 (fail-document "A regex option must be a JSON Boolean"
                                :path (cons name (cons "options" path))
                                :received option))
               (setf native (append native (list native-option option))))
      native)))

(defun wire-expression (value model allow-regex max-membership &optional path)
  (unless (and (json-array-p value) (plusp (length value)))
    (fail-document "A query expression must be a nonempty JSON array"
                   :path path :received value))
  (let* ((operator
           (external-name (aref value 0) +operator-names+ "query operator"
                          (cons 0 path)))
         (length (length value)))
    (when (and (member operator '(:regex-search :regex-full-match))
               (not allow-regex))
      (fail-document "Regex query nodes require :ALLOW-REGEX T"
                     :path (cons 0 path) :received operator))
    (labels ((arity (expected)
               (unless (= length expected)
                 (fail-document "A query expression has the wrong arity"
                                :path path :received (1- length))))
             (field (index)
               (registered-wire-field model (aref value index) (cons index path))))
      (case operator
        ((:and :or)
         (cons operator
               (loop for index from 1 below length
                     collect (wire-expression (aref value index) model allow-regex
                                              max-membership (cons index path)))))
        (:not
         (arity 2)
         (list operator
               (wire-expression (aref value 1) model allow-regex max-membership
                                (cons 1 path))))
        ((:present :missing)
         (arity 2)
         (list operator (libtmux.internal::field-spec-key (field 1))))
        ((:any :all :none :is)
         (arity 3)
         (let ((relation (field 1)))
           (unless (eq :relation (libtmux.internal::field-spec-kind relation))
             (fail-document "A relation operator requires a registered relation"
                            :path (cons 1 path) :received (aref value 1)))
           (list operator
                 (libtmux.internal::field-spec-key relation)
                 (wire-expression
                  (aref value 2) (libtmux.internal::field-spec-target relation)
                  allow-regex max-membership (cons 2 path)))))
        (:in
         (arity 3)
         (let ((field (field 1))
               (members (aref value 2)))
           (unless (json-array-p members)
             (fail-document "An IN operand must be a JSON array"
                            :path (cons 2 path) :received members))
           (when (> (length members) max-membership)
             (fail-document
              (format nil "Membership contains more than ~D operands" max-membership)
              :path (cons 2 path) :limit :max-membership
              :received (length members)))
           (list operator (libtmux.internal::field-spec-key field)
                 (map 'simple-vector
                      (lambda (member) (scalar-json-value member (cons 2 path)))
                      members))))
        ((:regex-search :regex-full-match)
         (arity 3)
         (let ((field (field 1)))
           (list operator (libtmux.internal::field-spec-key field)
                 (regex-wire-spec (aref value 2) (cons 2 path)))))
        (otherwise
         (arity 3)
         (let ((field (field 1)))
           (list operator (libtmux.internal::field-spec-key field)
                 (scalar-json-value (aref value 2) (cons 2 path)))))))))

(defun read-filter
    (source
     &key
       (allow-regex nil)
       (max-input-bytes +default-max-input-bytes+)
       (max-depth +default-max-depth+)
       (max-nodes +default-max-nodes+)
       (max-string-length +default-max-string-length+)
       (max-membership +default-max-membership+)
       (max-integer-digits +default-max-integer-digits+))
  "Read one bounded libtmux.lisp.filter/1 JSON string into a compiled filter.
External names resolve through closed registries and are never interned. Regex
nodes are rejected unless ALLOW-REGEX is true and libtmux/regex is loaded.
Parser limits bound UTF-8 input bytes, nesting, JSON nodes, strings, membership
arrays and integer-token digits. Decimal and exponent number syntax is rejected
before conversion. Parser limits do not interrupt CL-PPCRE execution."
  (unless (stringp source)
    (fail-document "READ-FILTER requires a complete JSON string" :received source))
  (unless (or (eq allow-regex t) (null allow-regex))
    (fail-document ":ALLOW-REGEX must be T or NIL" :received allow-regex))
  (checked-limit max-input-bytes :max-input-bytes 1)
  (checked-limit max-depth :max-depth 1)
  (checked-limit max-nodes :max-nodes 1)
  (checked-limit max-string-length :max-string-length 1)
  (checked-limit max-membership :max-membership 0)
  (checked-limit max-integer-digits :max-integer-digits 1)
  (bounded-utf-8-size source max-input-bytes)
  (validate-numeric-token-bounds source max-integer-digits)
  (let ((document (parse-bounded-json source max-depth max-nodes max-string-length)))
    (closed-object document +root-members+ nil)
    (let* ((schema (required-object-member document "schema" nil))
           (model-source (required-object-member document "model" nil))
           (version (required-object-member document "registryVersion" nil))
           (expression-source (required-object-member document "expression" nil)))
      (unless (and (stringp schema) (string= schema *schema*))
        (fail-document "Unsupported filter-document schema"
                       :path '("schema") :received schema))
      (let ((model (external-name model-source +model-names+ "query model"
                                  '("model"))))
        (unless (and (integerp version)
                     (= version libtmux.internal::+registry-version+))
          (fail-document "Unsupported query registry version"
                         :path '("registryVersion") :received version))
        (let ((native (wire-expression expression-source model allow-regex
                                       max-membership '("expression"))))
          (handler-case
              (libtmux.query:compile-filter
               model native
               :max-depth max-depth
               :max-input-visits (* 8 max-nodes)
               :max-membership max-membership
               :max-string-length max-string-length
               :max-retained-characters max-input-bytes)
            (libtmux.query:query-limit-exceeded (cause)
              (fail-document "Native query validation exhausted the document node bound"
                             :path '("expression") :limit :max-nodes
                             :cause cause))
            (libtmux.query:invalid-filter (cause)
              (fail-document "The filter document is not a valid native query"
                             :path '("expression") :cause cause))))))))

(defun write-field (writer key)
  (com.inuoe.jzon:write-value writer (field-name key)))

(defun write-regex-spec (writer spec)
  (com.inuoe.jzon:with-object writer
    (com.inuoe.jzon:write-key writer "engine")
    (com.inuoe.jzon:write-value writer "cl-ppcre")
    (com.inuoe.jzon:write-key writer "pattern")
    (com.inuoe.jzon:write-value writer (second spec))
    (com.inuoe.jzon:write-key writer "options")
    (com.inuoe.jzon:with-object writer
      (loop for (key value) on (cddr spec) by #'cddr
            for name = (car (rassoc key +regex-option-names+ :test #'eq))
            do (com.inuoe.jzon:write-key writer name)
               (com.inuoe.jzon:write-value writer value)))))

(defun write-expression (writer expression)
  (let ((operator (first expression)))
    (com.inuoe.jzon:with-array writer
      (com.inuoe.jzon:write-value writer (operator-name operator))
      (case operator
        ((:and :or)
         (dolist (child (rest expression)) (write-expression writer child)))
        (:not (write-expression writer (second expression)))
        ((:present :missing)
         (write-field writer (second expression)))
        ((:any :all :none :is)
         (write-field writer (second expression))
         (write-expression writer (third expression)))
        (:in
         (write-field writer (second expression))
         (com.inuoe.jzon:with-array writer
           (map nil (lambda (operand)
                      (com.inuoe.jzon:write-value writer operand))
                (third expression))))
        ((:regex-search :regex-full-match)
         (write-field writer (second expression))
         (write-regex-spec writer (third expression)))
        (otherwise
         (write-field writer (second expression))
         (com.inuoe.jzon:write-value writer (third expression)))))))

(defun write-filter-to-stream (filter stream pretty)
  (let* ((description (libtmux.query:explain filter))
         (model (getf description :model))
         (registry-version (getf description :registry-version)))
    (com.inuoe.jzon:with-writer
        (writer :stream stream :pretty pretty :max-depth nil)
      (com.inuoe.jzon:with-object writer
        (com.inuoe.jzon:write-key writer "schema")
        (com.inuoe.jzon:write-value writer *schema*)
        (com.inuoe.jzon:write-key writer "model")
        (com.inuoe.jzon:write-value writer (model-name model))
        (com.inuoe.jzon:write-key writer "registryVersion")
        (com.inuoe.jzon:write-value writer registry-version)
        (com.inuoe.jzon:write-key writer "expression")
        (write-expression writer (libtmux.query:expression filter))))))

(defun open-character-output-stream-p (value)
  (and (streamp value)
       (open-stream-p value)
       (output-stream-p value)
       (nth-value 0 (subtypep (stream-element-type value) 'character))))

(deftype open-character-output-stream ()
  '(and stream (satisfies open-character-output-stream-p)))

(defun write-filter (filter &key stream (pretty nil))
  "Serialize a COMPILED-FILTER as one libtmux.lisp.filter/1 JSON document.
Return a fresh string when STREAM is NIL; otherwise write to the supplied open
output character stream and return NIL without closing it. Pathnames and binary
streams are rejected. The wire contract is native to this port and does not
imply cross-port regex or query equivalence."
  (check-type filter libtmux.query:compiled-filter)
  (when stream (check-type stream open-character-output-stream))
  (if stream
      (progn (write-filter-to-stream filter stream pretty) nil)
      (with-output-to-string (output)
        (write-filter-to-stream filter output pretty))))
