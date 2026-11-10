(in-package #:libtmux.query)

(defun compile-tmux-filter (filter version)
  "Inspect a bounded scalar format for FILTER and exact native VERSION.
Return owned ASCII source or NIL, plus fresh capability metadata. This private
compiler performs no I/O and authorizes neither acquisition execution nor row
pruning. Its recursive expansion bound does not prevent native elapsed-time
failure. FILTER must be a COMPILED-FILTER; unsupported expressions fall back
as a whole. Local evaluation retains its full native Lisp scalar semantics."
  (check-type filter compiled-filter)
  (let* ((model (slot-value filter 'model))
         (profile
           (and (stringp version)
                (member version '("3.3a" "3.4" "3.5" "3.5a" "3.6" "3.6a"
                                  "3.6b" "3.7" "3.7a" "3.7b" "3.7c" "3.8")
                        :test #'string=)))
         (row (libtmux.internal::row-spec-for
               (if (eq model :window) :window-link model)))
         (visits 0) (bytes 0) (nesting 0))
    (labels
        ((metadata (reason)
           (list :model model :registry-version (slot-value filter 'registry-version)
                 :required-fields (required-fields filter)
                 :required-relations (required-relations filter)
                 :native-version (and profile (copy-seq version))
                 :listing (and profile
                               (libtmux.internal::owned-data
                                (libtmux.internal::row-spec-command row)))
                 :source-inspection (if reason :fallback :supported)
                 :fallback-reason reason
                 :source-bytes (unless reason bytes) :format-depth (unless reason nesting)
                 :node-visits (unless reason visits) :attempted-node-visits visits
                 :recursive-loop-upper-bound (unless reason (+ 8 (* 8 nesting)))
                 :acquires-p nil :execution :local :acquisition-execution :unavailable))
         (refuse (reason)
           (return-from compile-tmux-filter (values nil (metadata reason))))
         (emit (depth &rest pieces)
           (let ((size (reduce #'+ pieces :key #'length)))
             (setf bytes (max bytes size) nesting (max nesting depth))
             (when (> bytes 4096) (refuse :source-bytes))
             (when (> nesting 8) (refuse :source-depth))
             (cons (apply #'concatenate 'string pieces) depth)))
         (combine (operator left right)
           (emit (1+ (max (cdr left) (cdr right)))
                 "#{" operator ":" (car left) "," (car right) "}"))
         (group (operator children identity)
           (when (> (length children) (- 128 visits)) (refuse :source-nodes))
           (let ((parts (map 'vector #'walk children)))
             (labels ((balanced (start end)
                        (if (= 1 (- end start))
                            (aref parts start)
                            (let ((middle (floor (+ start end) 2)))
                              (combine operator (balanced start middle)
                                       (balanced middle end))))))
               (if (zerop (length parts)) (emit 0 identity)
                   (balanced 0 (length parts))))))
         (scalar (node)
           (let* ((key (query-node-field node))
                  (field (query-node-descriptor node))
                  (capture-field
                    (find key (libtmux.internal::row-spec-fields row)
                          :key #'libtmux.internal::field-spec-key :test #'eq))
                  (operand (query-node-operand node))
                  (operator (query-node-operator node)))
             (unless (and field (eq field capture-field)
                          (eq field (gethash key libtmux.internal::*field-registry*)))
               (refuse :registry-mismatch))
             (when (libtmux.internal::field-spec-optional field) (refuse :optional-field))
             (let ((kind (libtmux.internal::field-spec-kind field)))
               (unless (member kind '(:boolean :integer)) (refuse :unsupported-field-kind))
               (when (eq kind :integer)
                 (unless
                     (every (lambda (value)
                              (and (integerp value) (<= -4294967295 value 4294967295)))
                            (list operand (libtmux.internal::field-spec-minimum field)
                                  (libtmux.internal::field-spec-maximum field)))
                   (refuse :integer-domain)))
               (emit 2 "#{e|"
                     (ecase operator (:= "==") (:< "<") (:<= "<=") (:> ">") (:>= ">="))
                     ":#{" (libtmux.internal::field-spec-format field) "},"
                     (format nil "~D" (if (eq kind :boolean) (if operand 1 0) operand))
                     "}"))))
         (walk (node)
           (when (> (incf visits) 128) (refuse :source-nodes))
           (case (query-node-operator node)
             (:and (group "&&" (query-node-children node) "1"))
             (:or (group "||" (query-node-children node) "0"))
             (:not
              (let ((child (walk (aref (query-node-children node) 0))))
                (emit (1+ (cdr child)) "#{e|==:" (car child) ",0}")))
             ((:= :< :<= :> :>=) (scalar node))
             (otherwise (refuse :unsupported-operator)))))
      (unless profile (refuse :unsupported-profile))
      (when (and (eq model :client) (string= version "3.3a"))
        (refuse :listing-filter-unavailable))
      (unless (= (slot-value filter 'registry-version) libtmux.internal::+registry-version+)
        (refuse :registry-mismatch))
      (let ((source (car (walk (slot-value filter 'root)))))
        (values source (metadata nil))))))
