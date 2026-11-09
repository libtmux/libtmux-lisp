(in-package #:libtmux.workspace)

(defclass owned-inspection ()
  ((data :initarg :data) (snapshots :initarg :snapshots)
   (outcomes :initarg :outcomes) (causes :initarg :causes))
  (:documentation "Private read evidence, including incomplete work; never a ready planning input."))

(define-condition owned-inspection-error (workspace-error)
  ((inspection :initarg :inspection) (terminal :initarg :terminal))
  (:documentation "Inspection stopped; prior evidence and the terminal failure remain separate."))

(defun owned-inspection-data (value) (deep-copy (slot-value value 'data)))
(defun owned-inspection-snapshots (value) (copy-seq (slot-value value 'snapshots)))
(defun owned-inspection-outcomes (value) (copy-seq (slot-value value 'outcomes)))
(defun owned-inspection-causes (value) (copy-seq (slot-value value 'causes)))
(defun owned-inspection-error-evidence (condition) (slot-value condition 'inspection))
(defun owned-inspection-error-terminal (condition) (slot-value condition 'terminal))

(defstruct inspection-attempt reader start end complete-p opening closing opening-inventory closing-inventory roles diagnostics
  (invalid-keys (make-hash-table :test #'equal)))
(defstruct inspection-run attempts causes)

(defun inspection-note (run attempt role cause)
  (push cause (inspection-run-causes run))
  (push (list :role role :message (princ-to-string cause)) (inspection-attempt-diagnostics attempt)))

(defun inspection-invalid (run attempt role message)
  (inspection-note run attempt role (make-condition 'invalid-workspace :message message)))

(defun inspection-metadata (run attempt role function)
  (handler-case (funcall function)
    (workspace-error (cause)
      (when (workspace-limit cause) (error cause))
      (inspection-note run attempt role cause)
      nil)))

(defun inspection-bundle (run attempt role kind revision &key reference required validator)
  (let* ((reader (inspection-attempt-reader attempt))
         (entry (list :role role :kind kind :revision revision :status :unread :header nil :record nil)))
    (push entry (inspection-attempt-roles attempt))
    (handler-case
        (multiple-value-bind (record header status)
            (owned-read-bundle-parts reader kind revision reference
                                    (lambda (header) (setf (getf entry :header) header)))
          (setf (getf entry :status) status (getf entry :header) header)
          (when record (setf (getf entry :record) (slot-value record 'data)))
          (when (and required (not record))
            (inspection-invalid run attempt role "A required selected workspace record is absent or incomplete"))
          (when (and record validator) (funcall validator record))
          record)
      (workspace-error (cause)
        (when (workspace-limit cause) (error cause))
        (setf (getf entry :status) :invalid)
        (inspection-note run attempt role cause)
        nil))))

(defun inspection-intent-binding (record base declaration)
  (let ((data (slot-value record 'data)))
    (unless (and (string= base (getf data :base))
                 (or (null declaration)
                     (string= (owned-json (encode-owned-declaration declaration))
                              (owned-json (encode-owned-declaration (getf data :declaration))))))
      (fail-workspace "Selected workspace intent does not bind its base and declaration"))))

(defun inspection-candidate-binding (attempt record head)
  (let* ((data (slot-value record 'data)) (previous (getf data :previous))
         (roles (inspection-attempt-roles attempt))
         (base (find :base roles :key (lambda (role) (getf role :role))))
         (pending (find :writer-pending roles :key (lambda (role) (getf role :role)))))
    (unless (if (string= head "0") (null previous)
                (and previous (string= head (getf previous :revision))))
      (fail-workspace "Unpublished workspace candidate names another base revision"))
    (dolist (pair (list (cons previous (getf base :header))
                       (cons (getf data :pending) (getf pending :header))))
      (when (cdr pair)
        (unless (every (lambda (key) (equal (getf (car pair) key) (getf (cdr pair) key))) '(:revision :bytes :chunks))
          (fail-workspace "Unpublished workspace candidate disagrees with a selected descriptor"))))
    (let ((intent (owned-reader-pending (inspection-attempt-reader attempt))))
      (when intent (inspection-intent-binding intent head (getf data :declaration))))))

(defun inspection-read-records (run attempt control)
  (let* ((reader (inspection-attempt-reader attempt))
         (busy (eq :busy (getf control :state))) (head (getf control :head))
         (writer (getf control :writer))
         (base (unless (string= head "0")
                 (inspection-bundle run attempt :base :committed head :required t))))
    (when base (setf (owned-reader-committed reader) base))
    (when busy
      (setf (owned-reader-pending reader)
            (inspection-bundle run attempt :writer-pending :pending writer
                               :validator (lambda (record) (inspection-intent-binding record head nil))))
      (inspection-bundle run attempt :unpublished :committed writer
                         :validator (lambda (record) (inspection-candidate-binding attempt record head))))
    (when base
      (let* ((data (slot-value base 'data)) (previous (getf data :previous)))
        (when previous
          (setf (owned-reader-previous reader)
                (inspection-bundle run attempt :previous :committed (getf previous :revision)
                                   :reference previous :required (not busy))))
        (let ((intent (inspection-bundle
                       run attempt (if busy :base-pending :current-pending) :pending head
                       :reference (getf data :pending) :required (not busy)
                       :validator (lambda (record)
                                    (inspection-intent-binding record
                                                               (if previous (getf previous :revision) "0")
                                                               (getf data :declaration))))))
          (unless busy (setf (owned-reader-pending reader) intent)))))))

(defun inspection-read-inventory (run attempt)
  (owned-read-inventory
   (inspection-attempt-reader attempt)
   :invalid-key (lambda (key cause)
                  (unless (gethash key (inspection-attempt-invalid-keys attempt))
                    (setf (gethash key (inspection-attempt-invalid-keys attempt)) t)
                    (inspection-note run attempt (list :inventory key) cause)))))

(defun check-inspection-inventory (run attempt)
  (let* ((reader (inspection-attempt-reader attempt))
         (id (getf (slot-value (owned-reader-declaration reader) 'data) :id))
         (selected (make-hash-table :test #'equal)))
    (setf (gethash (concatenate 'string (owned-namespace id) "control") selected) t)
    (dolist (role (inspection-attempt-roles attempt))
      (let ((kind (getf role :kind)) (revision (getf role :revision)) (header (getf role :header)))
        (setf (gethash (owned-record-key id kind revision) selected) t)
        (when header
          (dotimes (index (getf header :chunks))
            (setf (gethash (owned-record-key id kind revision index) selected) t)))))
    (loop for key across (owned-reader-inventory reader)
          unless (or (gethash key selected) (gethash key (inspection-attempt-invalid-keys attempt)))
            do (setf (gethash key (inspection-attempt-invalid-keys attempt)) t)
               (inspection-invalid run attempt (list :inventory key)
                                   "Workspace inventory contains a key not selected by this bounded read"))))

(defun check-inspection-vacancy (run attempt)
  (let ((reader (inspection-attempt-reader attempt)))
    (when (and (null (inspection-attempt-opening attempt))
               (or (plusp (length (owned-reader-inventory reader)))
                   (find (getf (getf (slot-value (owned-reader-declaration reader) 'data) :session) :name)
                         (libtmux:sessions (owned-reader-snapshot reader)) :key #'libtmux:name :test #'string=)))
      (unless (eq :unclaimed (owned-reader-status reader))
        (inspection-invalid run attempt :vacancy "Namespace or session name is not vacant"))
      (setf (owned-reader-status reader) :unclaimed))))

(defun inspection-read-attempt (run attempt)
  (let* ((reader (inspection-attempt-reader attempt))
         (opening (owned-read-control reader))
         (control nil))
    (setf (inspection-attempt-opening attempt) opening)
    (setf (inspection-attempt-opening-inventory attempt) (copy-seq (inspection-read-inventory run attempt)))
    (when opening
      (setf control (inspection-metadata run attempt :control (lambda () (parse-owned-control opening)))))
    (setf (owned-reader-status reader) (cond (control (getf control :state)) (opening :invalid) (t :vacant)))
    (when control (inspection-read-records run attempt control))
    (check-inspection-inventory run attempt)
    (let ((snapshot (owned-read-graph reader)))
      (owned-read-groups reader snapshot)
      (owned-read-geometry reader snapshot)
      (when (owned-reader-committed reader)
        (inspection-metadata run attempt :base-graph
                             (lambda () (validate-owned-graph (owned-reader-committed reader) snapshot))))
      (check-inspection-vacancy run attempt))
    (setf (inspection-attempt-closing-inventory attempt) (copy-seq (inspection-read-inventory run attempt)))
    (check-inspection-inventory run attempt)
    (check-inspection-vacancy run attempt)
    (setf (inspection-attempt-closing attempt) (owned-read-control reader))
    (owned-reader-check reader)
    (setf (inspection-attempt-end attempt) (libtmux.internal::monotonic-seconds)
          (inspection-attempt-complete-p attempt) t)
    (when (not (equal opening (inspection-attempt-closing attempt)))
      (setf (owned-reader-status reader) :changed)
      t)))

(defun inspection-attempt-data (attempt client)
  (let ((data (owned-reader-data (inspection-attempt-reader attempt) client (inspection-attempt-start attempt))))
    (when (inspection-attempt-end attempt)
      (setf (getf data :acquired-end) (inspection-attempt-end attempt)))
    (setf (getf data :inventory) (deep-copy (or (inspection-attempt-closing-inventory attempt)
                                             (inspection-attempt-opening-inventory attempt))))
    (append data
            (deep-copy
             (list :complete-p (inspection-attempt-complete-p attempt)
                   :opening-control (inspection-attempt-opening attempt)
                   :closing-control (inspection-attempt-closing attempt)
                   :opening-inventory (inspection-attempt-opening-inventory attempt)
                   :closing-inventory (inspection-attempt-closing-inventory attempt)
                   :roles (coerce (reverse (inspection-attempt-roles attempt)) 'simple-vector)
                   :diagnostics (coerce (reverse (inspection-attempt-diagnostics attempt)) 'simple-vector))))))

(defun finish-owned-inspection (run client budget &key (complete-p t))
  (let ((attempts (reverse (inspection-run-attempts run))))
    (make-instance
     'owned-inspection
     :data (list :complete-p complete-p
                 :status (if attempts (owned-reader-status (inspection-attempt-reader (car (last attempts)))) :incomplete)
                 :attempts (map 'simple-vector (lambda (attempt) (inspection-attempt-data attempt client)) attempts))
     :snapshots (map 'simple-vector (lambda (attempt) (owned-reader-snapshot (inspection-attempt-reader attempt))) attempts)
     :outcomes (coerce (reverse (libtmux.internal::capture-budget-outcomes budget)) 'simple-vector)
     :causes (coerce (reverse (inspection-run-causes run)) 'simple-vector))))

(defun inspect-owned-state (client declaration &key cancel-token
                                               (timeout (slot-value client 'libtmux::timeout))
                                               (output-limit (slot-value client 'libtmux::output-limit))
                                               (record-limit 100000))
  "Explicitly acquire incomplete read evidence; never return a ready state or mutate."
  (let ((run (make-inspection-run)))
    (call-with-owned-reader
     client declaration cancel-token timeout output-limit record-limit
     (lambda (reader start)
       (loop for index from 0 to 1
             for current = reader then
               (make-owned-reader :core (owned-reader-core reader) :declaration declaration
                                  :witness (owned-reader-witness reader) :context (owned-reader-context reader)
                                  :generation (owned-reader-generation reader)
                                  :row-counter (owned-reader-row-counter reader) :attempt index)
             for attempt = (make-inspection-attempt :reader current
                                                   :start (if (zerop index) start (libtmux.internal::monotonic-seconds)))
             do (push attempt (inspection-run-attempts run))
                (unless (inspection-read-attempt run attempt)
                  (return (finish-owned-inspection run client
                           (libtmux.internal::configuration-reader-budget (owned-reader-core reader)))))
                (when (= index 1) (fail-workspace "Workspace control changed during both inspection attempts"))))
     (lambda (reader primary terminal causes budget start)
       (declare (ignore reader primary causes start))
       (let ((attempt (first (inspection-run-attempts run))))
         (when (and attempt (null (inspection-attempt-end attempt)))
           (setf (inspection-attempt-end attempt) (libtmux.internal::monotonic-seconds))))
       (unless (member terminal (inspection-run-causes run)) (push terminal (inspection-run-causes run)))
       (let ((inspection (finish-owned-inspection run client budget :complete-p nil)))
         (error 'owned-inspection-error :client client :inspection inspection :terminal terminal
                :cause (aref (slot-value inspection 'causes) 0)
                :message (format nil "Workspace inspection stopped: ~A" terminal)))))))
