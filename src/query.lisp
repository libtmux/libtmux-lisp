(defpackage #:libtmux.query
  (:use #:cl)
  (:documentation "Validated native queries over finite captured libtmux observations.
Loading this package adds no transport dependency and performs no tmux I/O.")
  (:export
   #:compiled-filter #:compile-filter #:predicate #:matching
   #:fields #:expression #:required-fields #:required-relations #:explain
   #:query-set #:from #:where #:where-if #:order-by #:items #:query-set-model
   #:one #:one-or-none
   #:invalid-filter #:invalid-query-target #:query-limit-exceeded
   #:no-match #:ambiguous-match
   #:error-path #:error-operator #:error-expected #:error-received
   #:match-count #:count-exact-p #:match-sample))

(in-package #:libtmux.query)

(defgeneric error-path (condition)
  (:documentation "Return a fresh bounded vector locating the invalid query input."))
(defgeneric error-operator (condition)
  (:documentation "Return a bounded invalid-operator summary, or NIL."))
(defgeneric error-expected (condition)
  (:documentation "Return an owned bounded description of the expected query shape or type."))
(defgeneric error-received (condition)
  (:documentation "Return a safe bounded description of the received query value or target."))
(defgeneric match-count (condition)
  (:documentation "Return the known cardinality associated with a selection condition."))
(defgeneric count-exact-p (condition)
  (:documentation "Return true when MATCH-COUNT is exact, false when it is a lower bound."))

(define-condition invalid-filter (libtmux:libtmux-error)
  ((model :initarg :model :reader libtmux:error-model)
   (path :initarg :path :initform #())
   (operator :initarg :operator :initform nil)
   (field :initarg :field :initform nil :reader libtmux:error-field)
   (expected :initarg :expected :initform nil)
   (received :initarg :received :initform nil))
  (:documentation "A declarative filter is malformed, mistyped or exceeds a compile limit."))

(define-condition invalid-query-target (libtmux:libtmux-error)
  ((model :initarg :model :reader libtmux:error-model)
   (received :initarg :received))
  (:documentation "A compiled filter received an object outside its captured root model."))

(defmethod error-path ((condition invalid-filter))
  (copy-seq (slot-value condition 'path)))
(defmethod error-operator ((condition invalid-filter))
  (slot-value condition 'operator))
(defmethod error-expected ((condition invalid-filter))
  (libtmux.internal::owned-data (slot-value condition 'expected)))
(defmethod error-received ((condition invalid-filter))
  (libtmux.internal::owned-data (slot-value condition 'received)))
(defmethod error-received ((condition invalid-query-target))
  (libtmux.internal::owned-data (slot-value condition 'received)))

(define-condition query-limit-exceeded (invalid-filter) ()
  (:documentation "A bounded query compilation, execution or selection exhausted its budget."))

(define-condition no-match (libtmux:libtmux-error)
  ((count :initform 0 :reader match-count)
   (count-exact-p :initform t :reader count-exact-p)
   (sample :initform #()))
  (:documentation "Strict selection received no items."))

(define-condition ambiguous-match (libtmux:libtmux-error)
  ((count :initarg :count :reader match-count)
   (count-exact-p :initarg :count-exact-p :initform t :reader count-exact-p)
   (sample :initarg :sample :initform #()))
  (:documentation "Strict selection received more than one item."))

(defun match-sample (condition)
  "Return a fresh bounded vector of safe selected-item summaries."
  (libtmux.internal::owned-data (slot-value condition 'sample)))

(defstruct (query-node (:constructor make-query-node (operator function &key field operand children)))
  operator function field operand children)

(defstruct (execution-context (:constructor make-execution-context (model limit &key checker)))
  model limit (visits 0) checker)

(defun check-execution-interruption (context)
  (let ((checker (execution-context-checker context)))
    (when checker (funcall checker))))

(defun execution-checkpoint (context)
  (when (> (incf (execution-context-visits context))
           (execution-context-limit context))
    (error 'query-limit-exceeded :model (execution-context-model context)
           :received :execution
           :message (format nil "Query execution exceeds ~D expression visits"
                            (execution-context-limit context))))
  (check-execution-interruption context))

(defun evaluate-node (node entity context)
  (execution-checkpoint context)
  (multiple-value-prog1 (funcall (query-node-function node) entity context)
    (check-execution-interruption context)))

(defclass compiled-filter ()
  ((model :initarg :model)
   (expression :initarg :expression)
   (root :initarg :root)
   (required-fields :initarg :required-fields)
   (required-relations :initarg :required-relations)
   (registry-version :initarg :registry-version)
   (limits :initarg :limits)
   (execution-limit :initarg :execution-limit))
  (:documentation "An owned validated expression and reusable local evaluator."))

(defclass query-set ()
  ((contents :initarg :contents)
   (model :initarg :model :initform nil))
  (:documentation "An eager owned local selection with optional captured-model metadata."))

(defconstant +default-max-depth+ 64)
(defconstant +default-max-input-visits+ 10000)
(defconstant +default-max-membership+ 1000)
(defconstant +default-max-string-length+ 65536)
(defconstant +default-max-retained-characters+ 1048576)
(defconstant +default-max-selection-items+ 100000)
(defconstant +default-max-execution-visits+ 1000000)

(defstruct (operator-spec
             (:constructor make-operator-spec
                 (key arity field-kinds stage documentation)))
  key arity field-kinds stage documentation)

(defparameter *operator-specs*
  (map 'simple-vector
       (lambda (entry) (apply #'make-operator-spec entry))
       '((:= 2 (:text :integer :boolean) :scalar "Typed equality")
         (:< 2 (:integer) :scalar "Integer less-than")
         (:<= 2 (:integer) :scalar "Integer less-than or equal")
         (:> 2 (:integer) :scalar "Integer greater-than")
         (:>= 2 (:integer) :scalar "Integer greater-than or equal")
         (:in 2 (:text :integer :boolean) :scalar "Typed finite membership")
         (:contains 2 (:text) :scalar "Case-sensitive substring search")
         (:starts-with 2 (:text) :scalar "Case-sensitive text prefix")
         (:and :variadic () :scalar "Ordered conjunction; empty is true")
         (:or :variadic () :scalar "Ordered disjunction; empty is false")
         (:not 1 () :scalar "Boolean negation")
         (:present 1 (:text :integer :boolean) :scalar "Captured value is present")
         (:missing 1 (:text :integer :boolean) :scalar "Optional captured value is absent")
         (:any 2 (:relation) :relations "A related object matches")
         (:all 2 (:relation) :relations "Every related object matches")
         (:none 2 (:relation) :relations "No related object matches")
         (:is 2 (:relation) :relations "A to-one relation target matches")
         (:regex-search 2 (:text) :regex "CL-PPCRE search")
         (:regex-full-match 2 (:text) :regex "CL-PPCRE full match"))))

(defparameter *operator-registry*
  (let ((registry (make-hash-table :test 'eq)))
    (loop for spec across *operator-specs*
          do (setf (gethash (operator-spec-key spec) registry) spec))
    registry))

(defstruct compile-limits
  max-depth max-input-visits max-membership max-string-length
  max-retained-characters max-execution-visits)

(defvar *compile-path* nil)
(defvar *diagnostic-expected* nil)
(defvar *diagnostic-received* nil)

(defun query-model-class (model)
  (libtmux.internal::entity-model-class model))

(defun safe-designator-summary (value)
  (if (and (keywordp value) (<= (length (symbol-name value)) 64))
      value
      (type-of value)))

(defun fail-filter (model form control &rest arguments)
  (error 'invalid-filter :model (safe-designator-summary model)
         :path (coerce (reverse *compile-path*) 'simple-vector)
         :operator (and (consp form) (safe-designator-summary (first form)))
         :field (and (consp form) (consp (rest form))
                     (safe-designator-summary (second form)))
         :expected *diagnostic-expected*
         :received (or *diagnostic-received* (type-of form))
         :message (apply #'format nil control arguments)))

(defun limit-error (model form path control &rest arguments)
  (error 'query-limit-exceeded :model model
         :path (coerce (reverse path) 'simple-vector)
         :received (type-of form)
         :message (apply #'format nil control arguments)))

(defun validated-limit (model value name minimum)
  (unless (and (integerp value) (>= value minimum))
    (error 'invalid-filter :model model :expected `(integer ,minimum *)
           :received (type-of value)
           :message (format nil "~S must be an integer no smaller than ~D" name minimum)))
  value)

(defun validated-owned-form (model form limits)
  (let ((active (make-hash-table :test 'eq))
        (stack (list (list :visit form nil :root 1 nil 0 nil)))
        (root nil)
        (visits 0)
        (pending-visits 1)
        (characters 0))
    (labels ((assign (destination place value)
               (cond ((eq place :root) (setf root value))
                     ((eq place :car) (setf (car destination) value))
                     ((eq place :cdr) (setf (cdr destination) value))
                     ((integerp place) (setf (aref destination place) value))
                     (t (error "Unknown query copy destination"))))
             (visit (value path)
               (when (> (incf visits) (compile-limits-max-input-visits limits))
                 (limit-error model value path "Filter exceeds ~D input visits"
                              (compile-limits-max-input-visits limits))))
             (reserve-visits (count value path)
               (when (> (+ visits pending-visits count)
                        (compile-limits-max-input-visits limits))
                 (limit-error model value path "Filter exceeds ~D input visits"
                              (compile-limits-max-input-visits limits)))
               (incf pending-visits count))
             (enter (value depth path)
               (when (> depth (compile-limits-max-depth limits))
                 (limit-error model value path "Filter exceeds nesting depth ~D"
                              (compile-limits-max-depth limits)))
               (when (gethash value active)
                 (error 'invalid-filter :model model
                        :path (coerce (reverse path) 'simple-vector)
                        :received (type-of value)
                        :message "Filter data contains a cycle"))
               (setf (gethash value active) t)))
      (loop while stack
            for frame = (pop stack)
            do (destructuring-bind (action value destination place depth path position cdr-p)
                   frame
                 (when (eq action :visit) (decf pending-visits))
                 (ecase action
                   (:exit (remhash value active))
                   (:visit
                    (when (and cdr-p (not (or (null value) (consp value))))
                      (error 'invalid-filter :model model
                             :path (coerce (reverse path) 'simple-vector)
                             :received (type-of value)
                             :message "Filter data contains a dotted list"))
                    (visit value path)
                    (typecase value
                      (string
                       (when (> (length value) (compile-limits-max-string-length limits))
                         (limit-error model value path "String exceeds ~D characters"
                                      (compile-limits-max-string-length limits)))
                       (when (> (incf characters (length value))
                                (compile-limits-max-retained-characters limits))
                         (limit-error model value path
                                      "Filter retains more than ~D text characters"
                                      (compile-limits-max-retained-characters limits)))
                       (assign destination place (copy-seq value)))
                      (cons
                       (enter value depth path)
                       (reserve-visits 2 value path)
                       (let ((copy (cons nil nil)))
                         (assign destination place copy)
                         (push (list :exit value nil nil 0 nil 0 nil) stack)
                         (push (list :visit (cdr value) copy :cdr depth path
                                     (1+ position) t)
                               stack)
                         (push (list :visit (car value) copy :car (1+ depth)
                                     (cons position path) 0 nil)
                               stack)))
                      (vector
                       (enter value depth path)
                       (let ((length (length value)))
                         (reserve-visits length value path)
                         (let ((copy (make-array length)))
                           (assign destination place copy)
                           (push (list :exit value nil nil 0 nil 0 nil) stack)
                           (loop for index downfrom (1- length) to 0
                                 do (push (list :visit (aref value index) copy index
                                                (1+ depth) (cons index path) 0 nil)
                                          stack)))))
                      (t (assign destination place value)))))))
      (values root visits characters))))

(defun checked-field (model key operator)
  (let ((field (gethash key libtmux.internal::*field-registry*)))
    (if (and field (eq model (libtmux.internal::field-spec-model field)))
        field
        (let* ((safe-key (safe-designator-summary key))
               (cause (make-condition
                       'libtmux:field-unavailable :field safe-key :model model
                       :message "Field is not registered for the query model")))
          (error 'invalid-filter :model model :field safe-key
                 :path (coerce (reverse *compile-path*) 'simple-vector)
                 :operator operator
                 :expected :registered-field-for-model
                 :received safe-key :cause cause
                 :message (libtmux:error-message cause))))))

(defun record-requirement (key requirements seen)
  (unless (gethash key seen)
    (setf (gethash key seen) t)
    (vector-push-extend key requirements)))

(defun scalar-equality (kind)
  (ecase kind (:text #'string=) (:integer #'=) (:boolean #'eq)))

(defun normalize-scalar-operand (model form field operand)
  (let ((kind (libtmux.internal::field-spec-kind field))
        (key (libtmux.internal::field-spec-key field)))
    (unless (ecase kind
              (:text (stringp operand))
              (:integer (integerp operand))
              (:boolean (or (eq operand t) (null operand))))
      (let ((*diagnostic-expected* kind)
            (*diagnostic-received* (type-of operand)))
        (fail-filter model form "Operand for ~S must have field type ~S" key kind)))
    operand))

(defun scalar-field (model form operator requirements seen)
  (let* ((key (second form))
         (field (checked-field model key operator))
         (kind (libtmux.internal::field-spec-kind field))
         (spec (gethash operator *operator-registry*)))
    (unless (member kind (operator-spec-field-kinds spec))
      (let ((*diagnostic-expected* (operator-spec-field-kinds spec))
            (*diagnostic-received* kind))
        (fail-filter model form "Operator ~S does not accept ~S field ~S"
                     operator kind key)))
    (record-requirement key requirements seen)
    field))

(defun relation-field (model form operator requirements seen)
  (let* ((key (second form))
         (field (checked-field model key operator))
         (kind (libtmux.internal::field-spec-kind field))
         (cardinality (libtmux.internal::field-spec-cardinality field))
         (expected-cardinality (if (eq operator :is) :one :many)))
    (unless (eq kind :relation)
      (let ((*diagnostic-expected* :relation)
            (*diagnostic-received* kind))
        (fail-filter model form "Operator ~S requires a relation field" operator)))
    (unless (eq cardinality expected-cardinality)
      (let ((*diagnostic-expected* expected-cardinality)
            (*diagnostic-received* cardinality))
        (fail-filter model form "Operator ~S requires a ~S relation"
                     operator expected-cardinality)))
    (record-requirement key requirements seen)
    field))

(defun compile-node
    (model form requirements seen relation-requirements relation-seen limits
     &optional path)
  (let ((*compile-path* path))
    (unless (consp form)
      (let ((*diagnostic-expected* :nonempty-list))
        (fail-filter model form "A filter expression must be a nonempty list")))
    (let* ((operator (first form))
           (spec (gethash operator *operator-registry*)))
    (unless spec
      (let ((*diagnostic-expected* :registered-query-operator)
            (*diagnostic-received* (safe-designator-summary operator)))
        (fail-filter model form "Unsupported native query operator")))
    (when (eq :regex (operator-spec-stage spec))
      (let ((*diagnostic-expected* :scalar)
            (*diagnostic-received* (operator-spec-stage spec)))
        (fail-filter model form
                     "Operator ~S requires the unloaded libtmux/regex system"
                     operator)))
    (unless (or (eq :variadic (operator-spec-arity spec))
                (= (operator-spec-arity spec) (length (rest form))))
      (let ((*diagnostic-expected* (operator-spec-arity spec))
            (*diagnostic-received* (length (rest form))))
        (fail-filter model form "Operator ~S expects ~D operands"
                     operator (operator-spec-arity spec))))
    (case operator
      (:and
       (let ((children
               (coerce (loop for child in (rest form)
                             for index from 1
                             collect (compile-node model child requirements seen
                                                   relation-requirements relation-seen limits
                                                   (cons index path)))
                       'simple-vector)))
         (make-query-node
          operator
          (lambda (entity context)
            (loop for child across children
                  always (evaluate-node child entity context)))
          :children children)))
      (:or
       (let ((children
               (coerce (loop for child in (rest form)
                             for index from 1
                             collect (compile-node model child requirements seen
                                                   relation-requirements relation-seen limits
                                                   (cons index path)))
                       'simple-vector)))
         (make-query-node
          operator
          (lambda (entity context)
            (loop for child across children
                  thereis (evaluate-node child entity context)))
          :children children)))
      (:not
       (unless (= 2 (length form))
         (fail-filter model form "Operator :NOT expects one child"))
       (let ((child (compile-node model (second form) requirements seen
                                  relation-requirements relation-seen limits
                                  (cons 1 path))))
         (make-query-node operator
                          (lambda (entity context)
                            (not (evaluate-node child entity context)))
                          :children (vector child))))
      ((:= :< :<= :> :>= :contains :starts-with)
       (unless (= 3 (length form))
         (fail-filter model form "Operator ~S expects a field and operand" operator))
       (let* ((field (scalar-field model form operator requirements seen))
              (kind (libtmux.internal::field-spec-kind field))
              (key (libtmux.internal::field-spec-key field))
              (operand (normalize-scalar-operand model form field (third form))))
         (when (and (member operator '(:< :<= :> :>=)) (not (eq kind :integer)))
           (fail-filter model form "Operator ~S requires an integer field" operator))
         (when (and (member operator '(:contains :starts-with)) (not (eq kind :text)))
           (fail-filter model form "Operator ~S requires a text field" operator))
         (let ((comparison
                 (case operator
                   (:= (scalar-equality kind))
                   (:< #'<) (:<= #'<=) (:> #'>) (:>= #'>=))))
           (make-query-node
            operator
            (lambda (entity context)
              (declare (ignore context))
              (multiple-value-bind (value present-p)
                  (libtmux.internal::resolved-field-value entity field)
                (and present-p
                     (case operator
                       ((:= :< :<= :> :>=) (funcall comparison value operand))
                       (:contains (not (null (search operand value :test #'char=))))
                       (:starts-with (and (<= (length operand) (length value))
                                          (string= operand value :end2 (length operand))))))))
            :field key :operand operand))))
      (:in
       (unless (= 3 (length form))
         (fail-filter model form "Operator :IN expects a field and finite sequence"))
       (let* ((field (scalar-field model form operator requirements seen))
              (kind (libtmux.internal::field-spec-kind field))
              (key (libtmux.internal::field-spec-key field))
              (source (third form)))
         (unless (or (listp source) (and (vectorp source) (not (stringp source))))
           (let ((*diagnostic-expected* '(or list non-string-vector))
                 (*diagnostic-received* (type-of source)))
             (fail-filter model form
                          "Operator :IN expects a list or non-string vector")))
         (when (> (length source) (compile-limits-max-membership limits))
           (error 'query-limit-exceeded
                  :model model
                  :path (coerce (reverse *compile-path*) 'simple-vector)
                  :operator operator
                  :field key
                  :expected (compile-limits-max-membership limits)
                  :received (length source)
                  :message (format nil "Membership contains more than ~D operands"
                                   (compile-limits-max-membership limits))))
         (let* ((operands (map 'simple-vector
                               (lambda (operand)
                                 (normalize-scalar-operand model form field operand))
                               source))
                (lookup (make-hash-table :test (if (eq kind :text) 'equal 'eql))))
           (loop for operand across operands do (setf (gethash operand lookup) t))
           (make-query-node
            operator
            (lambda (entity context)
              (declare (ignore context))
              (multiple-value-bind (value present-p)
                  (libtmux.internal::resolved-field-value entity field)
                (and present-p (not (null (gethash value lookup))))))
            :field key :operand operands))))
      ((:present :missing)
       (unless (= 2 (length form))
         (fail-filter model form "Operator ~S expects one field" operator))
       (let* ((field (scalar-field model form operator requirements seen))
              (key (libtmux.internal::field-spec-key field)))
         (make-query-node
          operator
          (lambda (entity context)
            (declare (ignore context))
            (let ((present-p
                    (nth-value 1 (libtmux.internal::resolved-field-value entity field))))
              (if (eq operator :present) present-p (not present-p))))
          :field key)))
      ((:any :all :none :is)
       (let* ((field (relation-field model form operator
                                     relation-requirements relation-seen))
              (key (libtmux.internal::field-spec-key field))
              (target (libtmux.internal::field-spec-target field))
              (child (compile-node target (third form) requirements seen
                                   relation-requirements relation-seen limits
                                   (cons 2 path))))
         (make-query-node
          operator
          (lambda (entity context)
            (multiple-value-bind (value present-p)
                (libtmux.internal::resolved-field-value entity field)
              (ecase operator
                (:is
                 (and present-p
                      (progn
                        (execution-checkpoint context)
                        (evaluate-node child value context))))
                (:any
                 (loop for related across value
                       thereis (progn
                                 (execution-checkpoint context)
                                 (evaluate-node child related context))))
                (:all
                 (loop for related across value
                       always (progn
                                (execution-checkpoint context)
                                (evaluate-node child related context))))
                (:none
                 (loop for related across value
                       never (progn
                               (execution-checkpoint context)
                               (evaluate-node child related context)))))))
          :field key :children (vector child))))
      ((:regex-search :regex-full-match)
       (fail-filter model form "Operator ~S requires an unloaded optional query system" operator))
      (otherwise
       (fail-filter model form "Unsupported native query operator ~S" operator))))))

(defun compile-filter
    (model form
     &key
       (max-depth +default-max-depth+)
       (max-input-visits +default-max-input-visits+)
       (max-membership +default-max-membership+)
       (max-string-length +default-max-string-length+)
       (max-retained-characters +default-max-retained-characters+)
       (max-execution-visits +default-max-execution-visits+))
  "Compile FORM for captured MODEL into an owned local filter.
Scalar and registered relation operators perform no I/O and never evaluate
FORM as Lisp code. Regex operators require the optional regex system.
Keyword limits bound container depth, input visits, membership size, copied
character counts and later predicate execution. Limit failures signal
QUERY-LIMIT-EXCEEDED; malformed or mistyped forms signal INVALID-FILTER."
  (let ((class (query-model-class model)))
    (unless class
      (let ((*diagnostic-expected* #(:session :window :pane :window-link :client))
            (*diagnostic-received* (safe-designator-summary model)))
        (fail-filter model form
                     "Unknown captured query model; expected a registered entity model")))
    (when (null form)
      (let ((*diagnostic-expected* :nonempty-list)
            (*diagnostic-received* 'null))
        (fail-filter model form "A bare NIL filter is invalid")))
    (let* ((limits
             (make-compile-limits
              :max-depth (validated-limit model max-depth :max-depth 1)
              :max-input-visits
              (validated-limit model max-input-visits :max-input-visits 1)
              :max-membership
              (validated-limit model max-membership :max-membership 0)
              :max-string-length
              (validated-limit model max-string-length :max-string-length 0)
              :max-retained-characters
              (validated-limit model max-retained-characters
                               :max-retained-characters 0)
              :max-execution-visits
              (validated-limit model max-execution-visits
                               :max-execution-visits 1)))
           (owned (validated-owned-form model form limits))
           (requirements (make-array 4 :adjustable t :fill-pointer 0))
           (seen (make-hash-table :test 'eq))
           (relation-requirements (make-array 4 :adjustable t :fill-pointer 0))
           (relation-seen (make-hash-table :test 'eq))
           (root (compile-node model owned requirements seen
                               relation-requirements relation-seen limits)))
      (make-instance 'compiled-filter :model model :expression owned
                     :root root :required-fields (coerce requirements 'simple-vector)
                     :required-relations
                     (coerce relation-requirements 'simple-vector)
                     :registry-version libtmux.internal::+registry-version+
                     :limits limits
                     :execution-limit max-execution-visits))))

(defun expression (filter)
  "Return a fresh ordinary-data copy of FILTER's canonical native expression."
  (check-type filter compiled-filter)
  (nth-value 0
    (validated-owned-form (slot-value filter 'model)
                          (slot-value filter 'expression)
                          (slot-value filter 'limits))))

(defun required-fields (filter)
  "Return a fresh vector of scalar fields in first-occurrence order."
  (check-type filter compiled-filter)
  (copy-seq (slot-value filter 'required-fields)))

(defun required-relations (filter)
  "Return a fresh vector of relation fields in first-occurrence order."
  (check-type filter compiled-filter)
  (copy-seq (slot-value filter 'required-relations)))

(defun field-description (field)
  (list :key (libtmux.internal::field-spec-key field)
        :model (libtmux.internal::field-spec-model field)
        :kind (libtmux.internal::field-spec-kind field)
        :optional-p (not (null (libtmux.internal::field-spec-optional field)))
        :wire-format (let ((format (libtmux.internal::field-spec-format field)))
                       (and format (copy-seq format)))
        :wire-minimum (libtmux.internal::field-spec-minimum field)
        :wire-maximum (libtmux.internal::field-spec-maximum field)
        :target (libtmux.internal::field-spec-target field)
        :cardinality (libtmux.internal::field-spec-cardinality field)))

(defun fields (model)
  "Return fresh field metadata for one captured query MODEL in key order.
MODEL is one of :SESSION, :WINDOW, :PANE, :WINDOW-LINK or :CLIENT. Wire bounds
describe capture decoding and do not restrict native query integer operands."
  (unless (query-model-class model)
    (let ((*diagnostic-expected* #(:session :window :pane :window-link :client))
          (*diagnostic-received* (safe-designator-summary model)))
      (fail-filter model nil
                   "Unknown captured query model; expected a registered entity model")))
  (map 'simple-vector #'field-description (libtmux.internal::model-fields model)))

(defun explain (filter)
  "Return fresh execution metadata for FILTER. Query execution is local and acquires nothing."
  (check-type filter compiled-filter)
  (list :model (slot-value filter 'model)
        :registry-version (slot-value filter 'registry-version)
        :required-fields (required-fields filter)
        :required-relations (required-relations filter)
        :execution :local
        :acquires-p nil
        :source-filtering :unavailable))

(defun evaluate-filter (filter entity context)
  (let* ((model (slot-value filter 'model))
         (class (query-model-class model)))
    (unless (and (typep entity class) (eq model (libtmux:entity-model entity)))
      (error 'invalid-query-target :model model :received (type-of entity)
             :message (format nil "Expected a captured ~S entity, received ~S"
                              model (type-of entity))))
    (evaluate-node (slot-value filter 'root) entity context)))

(defun predicate (filter)
  "Return a genuine one-argument function that evaluates FILTER locally.
Each invocation receives a fresh execution budget and performs no tmux I/O."
  (check-type filter compiled-filter)
  (lambda (entity)
    (evaluate-filter
     filter entity
     (make-execution-context (slot-value filter 'model)
                             (slot-value filter 'execution-limit)))))

(defun selection-limit-error (model limit)
  (error 'query-limit-exceeded :model model :received :selection
         :message (format nil "Selection contains more than ~D items" limit)))

(defun finite-selection-vector (values max-items &optional model)
  (validated-limit model max-items :max-items 0)
  (typecase values
    (query-set
     (finite-selection-vector (slot-value values 'contents) max-items
                              (or model (slot-value values 'model))))
    (string
     (error 'libtmux:invalid-argument
            :message "A query selection must be a list or non-string vector"))
    (vector
     (let ((length (length values)))
       (when (> length max-items) (selection-limit-error model max-items))
       (let ((copy (make-array length)))
         (loop for index below length do (setf (aref copy index) (aref values index)))
         copy)))
    (list
     (let ((seen (make-hash-table :test 'eq))
           (copy (make-array (min 16 max-items) :adjustable t :fill-pointer 0))
           (tail values)
           (count 0))
       (loop while (consp tail)
             do (when (gethash tail seen)
                  (error 'libtmux:invalid-argument
                         :message "A query selection list must not contain a cycle"))
                (setf (gethash tail seen) t)
                (when (> (incf count) max-items)
                  (selection-limit-error model max-items))
                (vector-push-extend (car tail) copy)
                (setf tail (cdr tail)))
       (unless (null tail)
         (error 'libtmux:invalid-argument
                :message "A query selection must be a proper list"))
       (coerce copy 'simple-vector)))
    (t
     (error 'libtmux:invalid-argument
            :message "A query selection must be a list or non-string vector"))))

(defun query-set-model (set)
  "Return SET's declared captured model, or NIL for untyped ordinary data."
  (check-type set query-set)
  (slot-value set 'model))

(defun items (set)
  "Return a fresh simple vector containing SET's selected items in order."
  (check-type set query-set)
  (copy-seq (slot-value set 'contents)))

(defun from (values &key model (max-items +default-max-selection-items+))
  "Copy finite VALUES into an eager local QUERY-SET.
VALUES is a proper list, non-string vector or another query set. MODEL may name
one registered captured entity model; omit it for unrestricted ordinary data."
  (when (and model (not (query-model-class model)))
    (error 'invalid-filter
           :model (safe-designator-summary model)
           :expected #(:session :window :pane :window-link :client)
           :received (safe-designator-summary model)
           :message "Unknown query-set model"))
  (let* ((source-model (and (typep values 'query-set)
                            (slot-value values 'model)))
         (result-model (or model source-model))
         (contents (finite-selection-vector values max-items result-model)))
    (when (and model source-model (not (eq model source-model)))
      (error 'invalid-query-target :model model :received source-model
             :message "Cannot relabel a query set with another model"))
    (when result-model
      (let ((class (query-model-class result-model)))
        (loop for value across contents
              unless (and (typep value class)
                          (eq result-model (libtmux:entity-model value)))
                do (error 'invalid-query-target :model result-model
                          :received (type-of value)
                          :message "Query-set item does not match its declared model"))))
    (make-instance 'query-set :contents contents :model result-model)))

(defun where
    (set filter &key (max-items +default-max-selection-items+)
                      max-execution-visits)
  "Return a new query set containing SET items accepted by compiled FILTER.
Evaluation is eager and local. FILTER supplies the result model; conflicting
declared model metadata signals INVALID-QUERY-TARGET before evaluation."
  (check-type set query-set)
  (check-type filter compiled-filter)
  (let ((set-model (slot-value set 'model))
        (filter-model (slot-value filter 'model)))
    (when (and set-model (not (eq set-model filter-model)))
      (error 'invalid-query-target :model filter-model :received set-model
             :message "Query-set model does not match the compiled filter"))
    (make-instance
     'query-set :model filter-model
     :contents (matching filter (slot-value set 'contents)
                         :max-items max-items
                         :max-execution-visits max-execution-visits))))

(defun where-if
    (set function &key (max-items +default-max-selection-items+))
  "Return a new query set selected by native FUNCTION in input order.
FUNCTION is called exactly once per item during this eager local traversal.
Its effects and call order are never optimized as declarative query data."
  (check-type set query-set)
  (unless (functionp function)
    (error 'libtmux:invalid-argument :message "WHERE-IF requires a function"))
  (let* ((input (finite-selection-vector set max-items))
         (result (make-array (min 16 (length input))
                             :adjustable t :fill-pointer 0)))
    (loop for value across input
          when (funcall function value)
            do (vector-push-extend value result))
    (make-instance 'query-set :model (slot-value set 'model)
                              :contents (coerce result 'simple-vector))))

(defun order-by
    (set predicate &key (key #'identity)
                        (max-items +default-max-selection-items+))
  "Return a new query set stably ordered by native PREDICATE and KEY.
Sorting mutates only a private simple-vector copy; SET remains unchanged."
  (check-type set query-set)
  (unless (and (functionp predicate) (functionp key))
    (error 'libtmux:invalid-argument
           :message "ORDER-BY requires predicate and key functions"))
  (let ((copy (finite-selection-vector set max-items)))
    (make-instance 'query-set :model (slot-value set 'model)
                              :contents (stable-sort copy predicate :key key))))

(defun matching
    (filter values
     &key (max-items +default-max-selection-items+) max-execution-visits)
  "Return a fresh simple vector of VALUES accepted by FILTER.
VALUES must be a finite list or non-string vector. The result preserves order,
multiplicity and the original captured handles. MAX-ITEMS bounds validation.
One execution budget is shared across the entire traversal; no I/O occurs."
  (check-type filter compiled-filter)
  (when (typep values 'query-set)
    (error 'libtmux:invalid-argument
           :message "MATCHING accepts lists and vectors; use WHERE for a query set"))
  (let* ((model (slot-value filter 'model))
         (input (finite-selection-vector values max-items model))
         (limit (if max-execution-visits
                    (validated-limit model max-execution-visits
                                     :max-execution-visits 1)
                    (slot-value filter 'execution-limit)))
         (context (make-execution-context model limit))
         (result (make-array (min 16 (length input)) :adjustable t :fill-pointer 0)))
    (loop for value across input
          when (evaluate-filter filter value context)
            do (vector-push-extend value result))
    (coerce result 'simple-vector)))

(defun safe-item-summary (item)
  (if (typep item 'libtmux:entity)
      (list :model (libtmux:entity-model item) :id (libtmux:id item))
      (type-of item)))

(defun ambiguity-sample (items)
  (let* ((length (min 2 (length items)))
         (sample (make-array length)))
    (loop for index below length
          do (setf (aref sample index) (safe-item-summary (aref items index))))
    sample))

(defun one (values &key (max-items +default-max-selection-items+))
  "Return the only item in finite VALUES.
Signal NO-MATCH for zero items or AMBIGUOUS-MATCH for more than one. The full
bounded container is validated before a candidate is returned. NIL is an item."
  (let* ((items (finite-selection-vector values max-items))
         (count (length items)))
    (case count
      (0 (error 'no-match :message "Strict selection found no items"))
      (1 (aref items 0))
      (otherwise
       (error 'ambiguous-match :count count :count-exact-p t
              :sample (ambiguity-sample items)
              :message (format nil "Strict selection found ~D items" count))))))

(defun one-or-none (values &key (max-items +default-max-selection-items+))
  "Return the only item and T, or NIL,NIL when finite VALUES is empty.
Signal AMBIGUOUS-MATCH for more than one item after validating the full bounded
container. A singleton containing NIL returns NIL,T."
  (let* ((items (finite-selection-vector values max-items))
         (count (length items)))
    (case count
      (0 (values nil nil))
      (1 (values (aref items 0) t))
      (otherwise
       (error 'ambiguous-match :count count :count-exact-p t
              :sample (ambiguity-sample items)
              :message (format nil "Strict selection found ~D items" count))))))
