(in-package #:libtmux.tests)

(in-suite query)

(defclass unprintable-query-value () ())

(defmethod print-object ((value unprintable-query-value) stream)
  (declare (ignore value stream))
  (error "Query diagnostics invoked caller printing"))

(test query-package-is-separately-loadable
  (is (find-package :libtmux.query)))

(test scalar-filter-preserves-false-and-absence
  (let* ((panes (libtmux:panes (synthetic-snapshot)))
         (result
           (if (and (fboundp 'libtmux.query:compile-filter)
                    (fboundp 'libtmux.query:matching))
               (libtmux.query:matching
                (libtmux.query:compile-filter
                 :pane '(:and (:= :pane/active nil)
                               (:missing :pane/current-path)))
                panes)
               :query-not-implemented)))
    (is (vectorp result))
    (when (vectorp result)
      (is (= 1 (length result)))
      (when (= 1 (length result))
        (is (string= "sh" (libtmux:current-command (aref result 0))))
        (is (null (nth-value 1
                            (libtmux:field-value (aref result 0)
                                                 :pane/current-path))))))))

(defun reference-equal-p (field left right)
  (cond ((member field '(:pane/current-command :pane/current-path :pane/title))
         (string= left right))
        ((member field '(:pane/width :pane/height :pane/index :pane/pid))
         (= left right))
        (t (eq left right))))

(defun reference-filter-p (form entity)
  (labels ((field (key)
             (multiple-value-list (libtmux:field-value entity key)))
           (walk (expression)
             (case (first expression)
               (:=
                (destructuring-bind (operator key operand) expression
                  (declare (ignore operator))
                  (destructuring-bind (value present-p) (field key)
                    (and present-p (reference-equal-p key value operand)))))
               ((:< :<= :> :>=)
                (destructuring-bind (operator key operand) expression
                  (destructuring-bind (value present-p) (field key)
                    (and present-p
                         (funcall (ecase operator
                                    (:< #'<) (:<= #'<=) (:> #'>) (:>= #'>=))
                                  value operand)))))
               (:in
                (destructuring-bind (operator key operands) expression
                  (declare (ignore operator))
                  (destructuring-bind (value present-p) (field key)
                    (and present-p
                         (some (lambda (operand)
                                 (reference-equal-p key value operand))
                               operands)))))
               (:contains
                (destructuring-bind (operator key operand) expression
                  (declare (ignore operator))
                  (destructuring-bind (value present-p) (field key)
                    (and present-p (not (null (search operand value :test #'char=)))))))
               (:starts-with
                (destructuring-bind (operator key operand) expression
                  (declare (ignore operator))
                  (destructuring-bind (value present-p) (field key)
                    (and present-p (<= (length operand) (length value))
                         (string= operand value :end2 (length operand))))))
               (:and (every #'walk (rest expression)))
               (:or (some #'walk (rest expression)))
               (:not (not (walk (second expression))))
               (:present (nth-value 1 (libtmux:field-value entity (second expression))))
               (:missing (not (nth-value 1 (libtmux:field-value entity (second expression))))))))
    (walk form)))

(defun compiled-result-row (form panes)
  (handler-case
      (let ((test (libtmux.query:predicate
                   (libtmux.query:compile-filter :pane form))))
        (loop for pane across panes collect (not (null (funcall test pane)))))
    (condition () :compile-error)))

(test scalar-operators-agree-with-native-semantics
  (let* ((panes (libtmux:panes (synthetic-snapshot)))
         (cases
           (list
            (list '(:= :pane/current-command "nvim") '(t nil))
            (list '(:= :pane/current-path "/srv/λ") '(t nil))
            (list '(:= :pane/width 120) '(t t))
            (list '(:= :pane/active nil) '(nil t))
            (list '(:< :pane/width 121) '(t t))
            (list '(:<= :pane/width 120) '(t t))
            (list '(:> :pane/width 119) '(t t))
            (list '(:>= :pane/width 120) '(t t))
            (list '(:in :pane/current-command ("vim" "nvim")) '(t nil))
            (list '(:in :pane/active (nil)) '(nil t))
            (list '(:in :pane/current-command ()) '(nil nil))
            (list '(:contains :pane/current-command "nv") '(t nil))
            (list '(:contains :pane/title "") '(t t))
            (list '(:starts-with :pane/current-command "nv") '(t nil))
            (list '(:starts-with :pane/title "") '(t t))
            (list '(:and) '(t t))
            (list '(:or) '(nil nil))
            (list '(:not (:= :pane/current-path "/srv/λ")) '(nil t))
            (list '(:present :pane/current-path) '(t nil))
            (list '(:missing :pane/current-path) '(nil t))
            (list '(:and (:= :pane/width 120) (:= :pane/active t)) '(t nil))
            (list '(:or (:= :pane/current-command "x") (:= :pane/active nil))
                  '(nil t))))
         (reference
           (loop for (form expected) in cases
                 collect (list expected
                               (loop for pane across panes
                                     collect (not (null (reference-filter-p form pane)))))))
         (compiled
           (loop for (form expected) in cases
                 collect (list expected (compiled-result-row form panes)))))
    (is (every (lambda (row) (equal (first row) (second row))) reference))
    (is (every (lambda (row) (equal (first row) (second row))) compiled))))

(test scalar-compilation-enforces-models-types-and-required-data
  (signals libtmux.query:invalid-filter (libtmux.query:compile-filter :pane nil))
  (signals libtmux.query:invalid-filter (libtmux.query:compile-filter :server '(:and)))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter (make-instance 'unprintable-query-value) '(:and)))
  (signals libtmux.query:invalid-filter
    (libtmux.query:fields (make-instance 'unprintable-query-value)))
  (handler-case
      (progn
        (libtmux.query:compile-filter
         :pane (list (make-instance 'unprintable-query-value) :ignored))
        (fail "Unprintable operator compiled"))
    (libtmux.query:invalid-filter (condition)
      (is (eq 'unprintable-query-value
              (libtmux.query:error-operator condition)))))
  (let ((large-field (make-symbol (make-string 1000 :initial-element #\X))))
    (handler-case
        (progn
          (libtmux.query:compile-filter :pane (list := large-field t))
          (fail "Unregistered field compiled"))
      (libtmux.query:invalid-filter (condition)
        (is (eq 'symbol (libtmux:error-field condition))))))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:= :pane/unknown 1)))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:= :window/name "editor")))
  (handler-case
      (progn
        (libtmux.query:compile-filter :pane '(:= :pane/width 3/2))
        (fail "Ratio operand compiled"))
    (libtmux.query:invalid-filter (condition)
      (is (eq :integer (libtmux.query:error-expected condition)))
      (is (subtypep (libtmux.query:error-received condition) 'rational))))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:< :pane/current-command "z")))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:contains :pane/width "12")))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:in :pane/current-command "nvim")))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:in :pane/active (0))))
  (handler-case
      (progn
        (libtmux.query:compile-filter :pane '(:not (:and) (:or)))
        (fail "Invalid NOT arity compiled"))
    (libtmux.query:invalid-filter (condition)
      (is (= 1 (libtmux.query:error-expected condition)))
      (is (= 2 (libtmux.query:error-received condition)))))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:present :pane/window)))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:any :pane/window (:and))))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:eval (delete-file "owned"))))
  (handler-case
      (progn
        (libtmux.query:compile-filter
         :pane '(:and (:= :pane/active t) (:or (:eval "owned"))))
        (fail "Nested invalid operator compiled"))
    (libtmux.query:invalid-filter (condition)
      (is (equalp #(2 1) (libtmux.query:error-path condition)))
      (is (eq :eval (libtmux.query:error-operator condition)))))
  (handler-case
      (progn
        (libtmux.query:compile-filter
         :pane '(:and (:or (:= :pane/unknown t))))
        (fail "Nested unknown field compiled"))
    (libtmux.query:invalid-filter (condition)
      (is (equalp #(1 1) (libtmux.query:error-path condition)))
      (is (eq := (libtmux.query:error-operator condition)))))
  (let* ((pane (aref (libtmux:panes (synthetic-snapshot)) 0))
         (wide (libtmux.query:predicate
                (libtmux.query:compile-filter :pane '(:> :pane/width -1))))
         (impossible (libtmux.query:predicate
                      (libtmux.query:compile-filter
                       :pane `(:= :pane/width ,(ash 1 200)))))
         (constant (libtmux.query:predicate
                    (libtmux.query:compile-filter :pane '(:and)))))
    (is (funcall wide pane))
    (is (not (funcall impossible pane)))
    (signals libtmux.query:invalid-query-target (funcall constant '(:pane/width 120)))
    (remhash :pane/active (slot-value pane 'libtmux::fields))
    (signals libtmux:field-unavailable
      (funcall (libtmux.query:predicate
                (libtmux.query:compile-filter :pane '(:= :pane/active t)))
               pane))))

(test query-forms-enforce-structural-resource-limits
  (is (typep (libtmux.query:compile-filter :pane '(:and)
                                           :max-input-visits 3)
             'libtmux.query:compiled-filter))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:compile-filter :pane '(:and) :max-input-visits 2))
  (is (typep (libtmux.query:compile-filter :pane '(:= :pane/active nil)
                                           :max-input-visits 7)
             'libtmux.query:compiled-filter))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:compile-filter :pane '(:= :pane/active nil)
                                  :max-input-visits 6))
  (is (typep (libtmux.query:compile-filter
              :pane '(:in :pane/current-command ("vim" "nvim"))
              :max-input-visits 11 :max-membership 2)
             'libtmux.query:compiled-filter))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:compile-filter
     :pane '(:in :pane/current-command ("vim" "nvim"))
     :max-input-visits 10))
  (is (typep (libtmux.query:compile-filter
              :pane '(:in :pane/current-command #("vim" "nvim"))
              :max-input-visits 9)
             'libtmux.query:compiled-filter))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:compile-filter
     :pane '(:in :pane/current-command #("vim" "nvim"))
     :max-input-visits 8))
  #+sbcl
  (let* ((source (make-array 20000 :initial-element :ignored))
         (form (list :and source))
         (before (sb-ext:get-bytes-consed)))
    (signals libtmux.query:query-limit-exceeded
      (libtmux.query:compile-filter :pane form :max-input-visits 4))
    (is (< (- (sb-ext:get-bytes-consed) before) 524288)))
  #+sbcl
  (let ((source :leaf))
    (dotimes (index 20)
      (let ((container (make-array 1000 :initial-element :ignored)))
        (setf (aref container 0) source
              source container)))
    (let* ((form (list :and source))
           (before (sb-ext:get-bytes-consed)))
      (signals libtmux.query:query-limit-exceeded
        (libtmux.query:compile-filter :pane form :max-input-visits 2000))
      (is (< (- (sb-ext:get-bytes-consed) before) 524288))))
  (is (typep (libtmux.query:compile-filter
              :pane '(:not (:and)) :max-depth 2)
             'libtmux.query:compiled-filter))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:compile-filter :pane '(:not (:and)) :max-depth 1))
  (is (typep (libtmux.query:compile-filter
              :pane '(:= :pane/current-command "nvim")
              :max-string-length 4 :max-retained-characters 4)
             'libtmux.query:compiled-filter))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:compile-filter :pane '(:= :pane/current-command "nvim")
                                  :max-string-length 3))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:compile-filter
     :pane '(:and (:= :pane/current-command "nvim")
                  (:= :pane/title "editor"))
     :max-retained-characters 9))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:compile-filter
     :pane '(:in :pane/current-command ("a" "b")) :max-membership 1))
  (handler-case
      (progn
        (libtmux.query:compile-filter
         :pane '(:and (:= :pane/active t)
                      (:or (:in :pane/width (1 2))))
         :max-membership 1)
        (fail "Oversized nested membership compiled"))
    (libtmux.query:query-limit-exceeded (condition)
      (is (equalp #(2 1) (libtmux.query:error-path condition)))
      (is (eq :in (libtmux.query:error-operator condition)))))
  (signals libtmux.query:invalid-filter
    (libtmux.query:compile-filter :pane '(:not (:and) . :dotted)
                                  :max-input-visits 20))
  (let ((form (list :and)))
    (setf (cdr form) form)
    (signals libtmux.query:invalid-filter
      (libtmux.query:compile-filter :pane form :max-input-visits 20)))
  (let ((form (list :not nil)))
    (setf (second form) form)
    (signals libtmux.query:invalid-filter
      (libtmux.query:compile-filter :pane form :max-input-visits 20)))
  (let* ((members (vector nil))
         (form (list :in :pane/current-command members)))
    (setf (aref members 0) form)
    (signals libtmux.query:invalid-filter
      (libtmux.query:compile-filter :pane form :max-input-visits 20)))
  (let* ((shared '(:= :pane/active t))
         (form (list :and shared shared)))
    (is (typep (libtmux.query:compile-filter :pane form :max-input-visits 19)
               'libtmux.query:compiled-filter))
    (signals libtmux.query:query-limit-exceeded
      (libtmux.query:compile-filter :pane form :max-input-visits 18))))

(test compiled-filters-own-input-and-inspection-data
  (let* ((pane (aref (libtmux:panes (synthetic-snapshot)) 0))
         (text (copy-seq "nvim"))
         (members (vector text "vim"))
         (source (list :and
                       (list :in :pane/current-command members)
                       (list := :pane/width 120)
                       (list := :pane/current-command text)))
         (filter (libtmux.query:compile-filter :pane source))
         (test (libtmux.query:predicate filter)))
    (setf (char text 0) #\X
          (aref members 0) "sh"
          (second source) '(:or))
    (is (funcall test pane))
    (is (equalp #(:pane/current-command :pane/width)
                (libtmux.query:required-fields filter)))
    (is (equalp #() (libtmux.query:required-relations filter)))
    (let ((inspection (libtmux.query:expression filter)))
      (setf (char (aref (third (second inspection)) 0) 0) #\Z)
      (setf (first inspection) :or)
      (is (funcall test pane)))
    (let ((description (libtmux.query:explain filter)))
      (is (eq :pane (getf description :model)))
      (is (eq :local (getf description :execution)))
      (is (null (getf description :acquires-p)))
      (setf (aref (getf description :required-fields) 0) :changed)
      (is (equalp #(:pane/current-command :pane/width)
                  (libtmux.query:required-fields filter))))
    (let ((catalog (libtmux.query:fields :pane)))
      (is (vectorp catalog))
      (is (find :pane/current-command catalog :key (lambda (entry) (getf entry :key))))
      (setf (getf (aref catalog 0) :key) :changed)
      (is (not (eq :changed (getf (aref (libtmux.query:fields :pane) 0) :key)))))
    (let* ((field (gethash :pane/current-command libtmux.internal::*field-registry*))
           (replacement
             (libtmux.internal::make-field-spec
              :pane/current-command :pane :integer :format "broken")))
      (unwind-protect
           (progn
             (setf (gethash :pane/current-command libtmux.internal::*field-registry*)
                   replacement)
             (is (funcall test pane)))
        (setf (gethash :pane/current-command libtmux.internal::*field-registry*) field)))))

(test matching-validates-finite-sequences-and-shares-one-execution-budget
  (let* ((panes (libtmux:panes (synthetic-snapshot)))
         (first (aref panes 0))
         (second (aref panes 1))
         (same-id-other-server
           (aref (libtmux:panes (synthetic-snapshot)) 0))
         (all (libtmux.query:compile-filter :pane '(:and)))
         (active (libtmux.query:compile-filter :pane '(:= :pane/active t)))
         (two-leaves
           (libtmux.query:compile-filter
            :pane '(:and (:= :pane/width 120) (:= :pane/active t))
            :max-execution-visits 5))
         (backing (vector :before first second :after))
         (displaced (make-array 2 :displaced-to backing :displaced-index-offset 1))
         (fill (make-array 3 :initial-contents (list first second first)
                          :fill-pointer 2)))
    (is (functionp (libtmux.query:predicate all)))
    (let ((from-list (libtmux.query:matching all (list first second first)))
          (from-displaced (libtmux.query:matching all displaced))
          (from-fill (libtmux.query:matching all fill)))
      (is (typep from-list 'simple-vector))
      (is (= 3 (length from-list)))
      (is (eq first (aref from-list 0)))
      (is (eq first (aref from-list 2)))
      (is (equalp panes from-displaced))
      (is (equalp panes from-fill)))
    (let ((cross-server
            (libtmux.query:matching all (vector first same-id-other-server))))
      (is (= 2 (length cross-server)))
      (is (equal (libtmux:id first) (libtmux:id same-id-other-server)))
      (is (not (libtmux:same-entity-p first same-id-other-server))))
    (let ((empty-a (libtmux.query:matching active (vector second)))
          (empty-b (libtmux.query:matching active (vector second))))
      (is (typep empty-a 'simple-vector))
      (is (zerop (length empty-a)))
      (is (not (eq empty-a empty-b))))
    (is (= 2 (length (libtmux.query:matching all panes :max-items 2))))
    (signals libtmux.query:query-limit-exceeded
      (libtmux.query:matching all panes :max-items 1))
    (signals libtmux.query:query-limit-exceeded
      (libtmux.query:matching two-leaves panes))
    (is (funcall (libtmux.query:predicate two-leaves) first))
    (is (not (funcall (libtmux.query:predicate two-leaves) second)))
    (signals libtmux:invalid-argument (libtmux.query:matching all "not a sequence"))
    (let ((cycle (list first)))
      (setf (cdr cycle) cycle)
      (signals libtmux:invalid-argument
        (libtmux.query:matching all cycle :max-items 4)))))

(test strict-cardinality-distinguishes-empty-nil-and-ambiguity
  (signals libtmux.query:no-match (libtmux.query:one #()))
  (is (equal '(nil nil) (multiple-value-list (libtmux.query:one-or-none #()))))
  (is (equal '(nil t) (multiple-value-list (libtmux.query:one-or-none #(nil)))))
  (is (null (libtmux.query:one #(nil))))
  (let ((mutation-count 0))
    (handler-case
        (let ((item (libtmux.query:one #(:first :second))))
          (declare (ignore item))
          (incf mutation-count)
          (fail "Ambiguous selection returned a candidate"))
      (libtmux.query:ambiguous-match (condition)
        (is (= 2 (libtmux.query:match-count condition)))
        (is (libtmux.query:count-exact-p condition))
        (is (= 2 (length (libtmux.query:match-sample condition))))))
    (is (zerop mutation-count)))
  (signals libtmux.query:query-limit-exceeded
    (libtmux.query:one #(1 2) :max-items 1))
  (signals libtmux:invalid-argument (libtmux.query:one "not a container"))
  (let ((cycle (list :item)))
    (setf (cdr cycle) cycle)
    (signals libtmux:invalid-argument (libtmux.query:one cycle :max-items 4))))

(test scalar-query-roots-remain-local-across-all-captured-models
  (let* ((libtmux.internal::*process-launched-hook*
           (lambda (job)
             (declare (ignore job))
             (error "Local query work attempted to launch a process")))
         (snapshot (synthetic-snapshot))
         (cases
           (list (list :session (aref (libtmux:sessions snapshot) 0)
                       '(:= :session/name "a"))
                 (list :window (aref (libtmux:windows snapshot) 0)
                       '(:= :window/name "shared"))
                 (list :pane (aref (libtmux:panes snapshot) 0)
                       '(:= :pane/current-command "nvim"))
                 (list :window-link (aref (libtmux:window-links snapshot) 0)
                       '(:= :link/active t))
                 (list :client (aref (libtmux:clients snapshot) 0)
                       '(:= :client/control-mode t)))))
    (is (every (lambda (entry)
                 (destructuring-bind (model entity form) entry
                   (funcall (libtmux.query:predicate
                             (libtmux.query:compile-filter model form))
                            entity)))
               cases))
    (is (every (lambda (model) (plusp (length (libtmux.query:fields model))))
               '(:session :window :pane :window-link :client)))
    (signals libtmux.query:invalid-filter (libtmux.query:fields :server))))

(test relation-quantifiers-preserve-child-and-empty-semantics
  (let* ((libtmux.internal::*process-launched-hook*
           (lambda (job)
             (declare (ignore job))
             (error "Relation query attempted to launch a process")))
         (snapshot (synthetic-snapshot))
         (window (aref (libtmux:windows snapshot) 0))
         (sessions (libtmux:sessions snapshot))
         (empty-clients (aref sessions 1))
         (same-pane
           (libtmux.query:compile-filter
            :window
            '(:any :window/panes
              (:and (:= :pane/active t)
                    (:= :pane/current-command "sh")))))
         (different-panes
           (libtmux.query:compile-filter
            :window
            '(:and
              (:any :window/panes (:= :pane/active t))
              (:any :window/panes (:= :pane/current-command "sh")))))
         (any-client
           (libtmux.query:compile-filter
            :session '(:any :session/clients (:= :client/control-mode t))))
         (all-clients
           (libtmux.query:compile-filter
            :session '(:all :session/clients (:= :client/control-mode nil))))
         (no-clients
           (libtmux.query:compile-filter
            :session '(:none :session/clients (:= :client/control-mode t))))
         (bounded
           (libtmux.query:compile-filter
            :window '(:any :window/panes (:= :pane/active t))
            :max-execution-visits 3)))
    (is (not (funcall (libtmux.query:predicate same-pane) window)))
    (is (funcall (libtmux.query:predicate different-panes) window))
    (is (not (funcall (libtmux.query:predicate any-client) empty-clients)))
    (is (funcall (libtmux.query:predicate all-clients) empty-clients))
    (is (funcall (libtmux.query:predicate no-clients) empty-clients))
    (is (funcall (libtmux.query:predicate bounded) window))
    (signals libtmux.query:query-limit-exceeded
      (libtmux.query:matching bounded (vector window) :max-execution-visits 2))))

(test relation-requirements-to-one-and-nested-models
  (let* ((snapshot (synthetic-snapshot))
         (session (aref (libtmux:sessions snapshot) 0))
         (pane (aref (libtmux:panes snapshot) 0))
         (filter
           (libtmux.query:compile-filter
            :session
            '(:any :session/window-links
              (:is :link/window
               (:any :window/panes
                (:and (:= :pane/active t)
                      (:= :pane/current-command "nvim")))))))
         (pane-window
           (libtmux.query:compile-filter
            :pane '(:is :pane/window (:= :window/name "shared"))))
         (relations (slot-value pane 'libtmux::relations)))
    (is (funcall (libtmux.query:predicate filter) session))
    (is (equalp #(:pane/active :pane/current-command)
                (libtmux.query:required-fields filter)))
    (is (equalp #(:session/window-links :link/window :window/panes)
                (libtmux.query:required-relations filter)))
    (let ((inspection (libtmux.query:required-relations filter)))
      (setf (aref inspection 0) :changed)
      (is (eq :session/window-links
              (aref (libtmux.query:required-relations filter) 0))))
    (multiple-value-bind (window loaded-p) (gethash :pane/window relations)
      (unwind-protect
           (progn
             (setf (gethash :pane/window relations) nil)
             (is (not (funcall (libtmux.query:predicate pane-window) pane)))
             (remhash :pane/window relations)
             (signals libtmux:field-unavailable
               (funcall (libtmux.query:predicate pane-window) pane)))
        (if loaded-p
            (setf (gethash :pane/window relations) window)
            (remhash :pane/window relations))))
    (signals libtmux.query:invalid-filter
      (libtmux.query:compile-filter
       :window '(:is :window/panes (:= :pane/active t))))
    (signals libtmux.query:invalid-filter
      (libtmux.query:compile-filter
       :pane '(:any :pane/window (:= :window/name "shared"))))))

(test eager-query-set-owns-containers-and-preserves-native-order
  (let* ((panes (libtmux:panes (synthetic-snapshot)))
         (first (aref panes 0))
         (second (aref panes 1))
         (source (vector first second first))
         (all (libtmux.query:from source :model :pane))
         (active-filter
           (libtmux.query:compile-filter :pane '(:= :pane/active t))))
    (setf (aref source 0) second)
    (is (eq :pane (libtmux.query:query-set-model all)))
    (let ((copy (libtmux.query:items all)))
      (is (typep copy 'simple-vector))
      (is (eq first (aref copy 0)))
      (setf (aref copy 0) nil)
      (is (eq first (aref (libtmux.query:items all) 0))))
    (let* ((active (libtmux.query:where all active-filter))
           (items (libtmux.query:items active)))
      (is (eq :pane (libtmux.query:query-set-model active)))
      (is (= 2 (length items)))
      (is (eq first (aref items 0)))
      (is (eq first (aref items 1)))
      (signals libtmux.query:ambiguous-match (libtmux.query:one active))
      (is (eq first
              (libtmux.query:one
               (libtmux.query:from (vector first) :model :pane)))))
    (let ((empty (libtmux.query:where
                  (libtmux.query:from #()) active-filter)))
      (is (eq :pane (libtmux.query:query-set-model empty)))
      (is (zerop (length (libtmux.query:items empty))))
      (is (equal '(nil nil)
                 (multiple-value-list (libtmux.query:one-or-none empty)))))))

(test query-set-native-predicates-and-stable-order-remain-explicit
  (let ((seen nil))
    (let ((selected
            (libtmux.query:where-if
             (libtmux.query:from #(3 1 2 1))
             (lambda (value) (push value seen) (oddp value)))))
      (is (equal '(3 1 2 1) (reverse seen)))
      (is (equalp #(3 1 1) (libtmux.query:items selected)))))
  (let* ((a (cons 1 :a))
         (x (cons 0 :x))
         (b (cons 1 :b))
         (source (vector a x b))
         (ordered
           (libtmux.query:order-by
            (libtmux.query:from source) '< :key 'car)))
    (is (equalp (vector x a b) (libtmux.query:items ordered)))
    (is (equalp (vector a x b) source)))
  (let* ((panes (libtmux:panes (synthetic-snapshot)))
         (filter (libtmux.query:compile-filter :pane '(:and))))
    (signals libtmux.query:invalid-query-target
      (libtmux.query:where
       (libtmux.query:from (list (aref panes 0)) :model :window)
       filter))
    (signals libtmux:invalid-argument
      (libtmux.query:matching
       filter (libtmux.query:from #() :model :window)))))

(test query-set-function-designators-resolve-once
  (let ((source (libtmux.query:from #(3 1 2 1)))
        (name (gensym "QUERY-PREDICATE"))
        (calls 0))
    (is (equalp #(3 1 1)
                (libtmux.query:items (libtmux.query:where-if source 'oddp))))
    (unwind-protect
         (progn
           (setf (symbol-function name)
                 (lambda (value)
                   (incf calls)
                   (setf (symbol-function name) (constantly nil))
                   (oddp value)))
           (is (equalp #(3 1 1)
                       (libtmux.query:items
                        (libtmux.query:where-if source name))))
           (is (= 4 calls))
           (is (zerop (length (libtmux.query:items
                              (libtmux.query:where-if source name))))))
      (fmakunbound name))
    (dolist (invalid (list name 'when 'if '(lambda (x) x)))
      (signals libtmux:invalid-argument
        (libtmux.query:where-if source invalid))
      (signals libtmux:invalid-argument
        (libtmux.query:order-by source invalid))
      (signals libtmux:invalid-argument
        (libtmux.query:order-by source '< :key invalid)))))
