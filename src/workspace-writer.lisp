(in-package #:libtmux.workspace)

(defun owned-record-writes (record)
  "Prepare owned chunk pairs followed by their descriptor, without I/O."
  (let* ((data (slot-value record 'data))
         (kind (slot-value record 'kind))
         (id (getf data :workspace))
         (revision (getf data (if (eq kind :pending) :writer :revision))))
    (multiple-value-bind (descriptor chunks) (encode-owned-record record)
      (concatenate 'simple-vector
                   (map 'vector (lambda (chunk index)
                                  (cons (owned-record-key id kind revision index) chunk))
                        chunks (loop for index below (length chunks) collect index))
                   (vector (cons (owned-record-key id kind revision) descriptor))))))

(defun owned-retirement-keys (id committed writer)
  "Derive only the old previous bundle and old intent from a validated record."
  (owned-token writer #(:writer) (make-owned-context :native))
  (unless committed (return-from owned-retirement-keys #()))
  (check-type committed owned-record)
  (let* ((data (slot-value committed 'data)) (head (getf data :revision)) (keys nil))
    (unless (and (eq :committed (slot-value committed 'kind))
                 (equal id (getf data :workspace)) (not (equal writer head)))
      (fail-workspace "Retirement must retain the current workspace and writer"))
    (labels ((bundle (kind reference)
               (when reference
                 (let* ((reference (owned-reference reference #(:retirement) (make-owned-context :native)))
                        (revision (getf reference :revision)))
                   (when (or (equal writer revision) (and (eq kind :committed) (equal head revision)))
                     (fail-workspace "Retirement cannot remove a protected revision"))
                   (dotimes (index (getf reference :chunks))
                     (push (owned-record-key id kind revision index) keys))
                   (push (owned-record-key id kind revision) keys)))))
      (bundle :committed (getf data :previous))
      (bundle :pending (getf data :pending)))
    (coerce (nreverse keys) 'simple-vector)))

(defclass owned-writer ()
  ((client :initarg :client) (declaration :initarg :declaration)
   (context :initarg :context) (generation :initarg :generation) (witness :initarg :witness)
   (head :initarg :head) (token :initarg :token) (control-key :initarg :control-key)
   (control :initarg :control) (pending :initarg :pending) (writes :initarg :writes)
   (retirement :initarg :retirement) (options :initarg :options) (deadline :initarg :deadline)
   (application-preconditions :initarg :application-preconditions :initform nil)
   (stage :initform :prepared) (outcomes :initform nil))
  (:documentation "Private owned writer with guarded operations and retained outcomes."))

(define-condition owned-writer-error (workspace-error)
  ((writer :initarg :writer))
  (:documentation "An owned writer step stopped; known outcomes remain retained."))

(defun owned-writer-data (writer)
  "Return fresh progress data without acquiring or advancing writer state."
  (deep-copy (list :stage (slot-value writer 'stage) :head (slot-value writer 'head)
                   :writer (slot-value writer 'token) :control-key (slot-value writer 'control-key)
                   :control (slot-value writer 'control)
                   :pending (slot-value (slot-value writer 'pending) 'data))))

(defun owned-writer-outcomes (writer)
  (coerce (reverse (slot-value writer 'outcomes)) 'simple-vector))

(defun owned-writer-retain (writer outcomes)
  (map nil (lambda (outcome)
             (unless (member outcome (slot-value writer 'outcomes))
               (push outcome (slot-value writer 'outcomes)))) outcomes))

(defun owned-writer-check (writer)
  (let ((client (slot-value writer 'client)))
    (unless (and (eq (slot-value writer 'context) (slot-value client 'libtmux::context))
                 (= (slot-value writer 'generation) (slot-value client 'libtmux::generation))
                 (libtmux.internal::same-witness-p (slot-value writer 'witness)
                                                  (slot-value client 'libtmux::witness)))
      (error 'libtmux:stale-target :client client
             :message "Workspace writer no longer belongs to the original client generation"))
    (check-workspace-deadline client (slot-value writer 'deadline))))

(defun owned-writer-call (writer stage function)
  (unless (eq stage (slot-value writer 'stage))
    (fail-workspace "Workspace writer cannot advance from its current stage"))
  (let ((completed nil))
    (setf (slot-value writer 'stage) :active)
    (unwind-protect
         (handler-case
             (progn
               (owned-writer-check writer)
               (multiple-value-prog1 (funcall function) (setf completed t)))
           (error (cause)
             (owned-writer-retain
              writer (typecase cause
                       (owned-state-error (owned-state-error-outcomes cause))
                       (libtmux:configuration-read-failed (libtmux:configuration-read-outcomes cause))
                       (libtmux:libtmux-error (let ((outcome (libtmux:error-outcome cause)))
                                               (when outcome (vector outcome))))))
             (error 'owned-writer-error :client (slot-value writer 'client) :writer writer
                    :cause cause :outcome (when (typep cause 'libtmux:libtmux-error) (libtmux:error-outcome cause))
                    :message "Owned workspace writer stopped; inspect retained outcomes before further action")))
      (unless completed (setf (slot-value writer 'stage) :failed)))))

(defun owned-writer-preconditions (writer &optional idle)
  (list (list nil (libtmux.internal::format-equal
                   (slot-value writer 'control-key)
                   (if idle (make-owned-control :idle (slot-value writer 'head))
                       (slot-value writer 'control))))))

(defun owned-writer-builder (writer key value &key unset only-if-unset)
  (let ((builder (libtmux.internal::configuration-mutation-builder
                  "set-option" :server '("-s") key value (not unset)
                  nil nil nil nil nil unset :only-if-unset only-if-unset)))
    (lambda (witness current)
      ;; Preflight may accept a replacement daemon when the command has no target.
      (owned-writer-check writer)
      (funcall builder witness current))))

(defun check-owned-writer-envelope (writer key value preconditions &key unset only-if-unset)
  (let* ((witness (slot-value writer 'witness))
         (builder (owned-writer-builder writer key value :unset unset :only-if-unset only-if-unset)))
    (libtmux.internal::check-command-envelope
     (libtmux.internal::guarded-command witness nil (funcall builder witness nil)
                                        "libtmux-00000000000000000000000000000000"
                                        (owned-metadata-preconditions writer preconditions)))))

(defun owned-metadata-preconditions (writer preconditions)
  (libtmux.internal::owned-dispatch-preconditions
   (append (slot-value writer 'application-preconditions) preconditions)))

(defun prepare-owned-writer (client declaration state &key writer-token cancel-token
                                                         (timeout (slot-value client 'libtmux::timeout))
                                                         (output-limit (slot-value client 'libtmux::output-limit))
                                                         total-timeout deadline application-preconditions)
  "Prepare bounded metadata before claiming; the supplied ready state confers no new authority."
  (check-type client libtmux:client)
  (check-type declaration owned-declaration)
  (check-type state owned-state)
  (libtmux.internal::check-limits timeout output-limit)
  (when total-timeout (libtmux.internal::check-limits total-timeout output-limit))
  (when (or (and deadline total-timeout) (and deadline (not (realp deadline))))
    (fail-workspace "Use one absolute deadline or one total timeout"))
  (let* ((start (libtmux.internal::monotonic-seconds))
         (data (slot-value state 'data)) (snapshot (slot-value state 'snapshot))
         (id (getf (slot-value declaration 'data) :id))
         (control (getf data :control))
         (head (if control (getf (parse-owned-control control) :head) "0"))
         (token (or writer-token (format nil "~32,'0X" (random (ash 1 128) (make-random-state t)))))
         (committed (when (getf data :committed) (make-owned-record :committed (getf data :committed)))))
    (unless (and (member (getf data :status) '(:vacant :owned))
                 (if control (eq :idle (getf (parse-owned-control control) :state)) (null committed))
                 (equal id (getf (getf data :declaration) :id))
                 (eq (slot-value snapshot 'libtmux::context) (slot-value client 'libtmux::context))
                 (= (slot-value snapshot 'libtmux::generation) (slot-value client 'libtmux::generation))
                 (equal (getf data :witness)
                        (libtmux.internal::witness-provenance (slot-value client 'libtmux::witness))))
      (fail-workspace "Workspace writer requires a ready observation from this client generation"))
    (let* ((busy (make-owned-control :busy head token))
           (pending (make-owned-record :pending
                      (list :schema "libtmux.lisp.workspace.pending/1" :workspace id :base head
                            :writer token :declaration (slot-value declaration 'data))))
           (writer (make-instance 'owned-writer :client client :declaration declaration
                     :context (slot-value snapshot 'libtmux::context)
                     :generation (slot-value snapshot 'libtmux::generation)
                     :witness (slot-value client 'libtmux::witness) :head head :token (copy-seq token)
                     :control-key (concatenate 'string (owned-namespace id) "control") :control busy
                     :pending pending :writes (owned-record-writes pending)
                     :retirement (owned-retirement-keys id committed token)
                     :options (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)
                     :application-preconditions (libtmux.internal::owned-dispatch-preconditions application-preconditions)
                     :deadline (or deadline (when total-timeout (+ start total-timeout))))))
      (check-owned-writer-envelope writer (slot-value writer 'control-key) busy
                                   (when control (owned-writer-preconditions writer t))
                                   :only-if-unset (null control))
      (let ((preconditions (owned-writer-preconditions writer)))
        (map nil (lambda (key) (check-owned-writer-envelope writer key nil preconditions :unset t))
             (slot-value writer 'retirement))
        (map nil (lambda (pair) (check-owned-writer-envelope writer (car pair) (cdr pair) preconditions
                                                           :only-if-unset t))
             (slot-value writer 'writes)))
      writer)))

(defun owned-writer-options (writer)
  (workspace-call-options (slot-value writer 'client) (slot-value writer 'options)
                          (slot-value writer 'deadline)))

(defun owned-writer-mutate (writer key value &key unset only-if-unset preconditions)
  (let ((libtmux.internal::*dispatch-preconditions* (owned-metadata-preconditions writer preconditions)))
    (let ((outcome (apply #'libtmux.internal::perform-command (slot-value writer 'client) nil
                         (list "set-option" key) :argument-builder
                         (owned-writer-builder writer key value :unset unset :only-if-unset only-if-unset)
                         (owned-writer-options writer))))
      (owned-writer-retain writer (vector outcome))
      outcome)))

(defun owned-writer-read (writer procedure)
  "Read under a separate core owner, bracketing data with the expected control."
  (let ((options (owned-writer-options writer)))
    (apply #'call-with-owned-reader (slot-value writer 'client) (slot-value writer 'declaration)
         (append (loop for key in '(:cancel-token :timeout :output-limit) collect (getf options key))
                 (list 100000
                       (lambda (reader start)
                         (declare (ignore start))
                         (owned-writer-check writer)
                         (flet ((check-control ()
                                  (unless (equal (slot-value writer 'control) (owned-read-control reader))
                                    (fail-workspace "Workspace control changed during metadata readback"))))
                           (check-control)
                           (multiple-value-prog1 (funcall procedure reader)
                             (check-control))))
                       nil
                       (lambda (budget)
                         (owned-writer-retain
                          writer (reverse (libtmux.internal::capture-budget-outcomes budget)))))))))

(defun claim-owned-writer (writer)
  "Claim once and require exact token readback; failed observation never repeats the write."
  (owned-writer-call
   writer :prepared
   (lambda ()
     (let ((genesis (string= "0" (slot-value writer 'head))))
       (owned-writer-mutate writer (slot-value writer 'control-key) (slot-value writer 'control)
                            :only-if-unset genesis
                            :preconditions (unless genesis (owned-writer-preconditions writer t))))
     (owned-writer-read writer (lambda (reader) (declare (ignore reader)) nil))
     (setf (slot-value writer 'stage) :claimed)
     writer)))

(defun retire-owned-writer-records (writer)
  "Retire only known obsolete keys under BUSY; already-absent keys require no mutation."
  (owned-writer-call
   writer :claimed
   (lambda ()
     (map nil (lambda (key)
                (multiple-value-bind (value present-p)
                    (owned-writer-read writer (lambda (reader) (owned-read-leaf reader key 4096)))
                  (declare (ignore value))
                  (when present-p
                    (owned-writer-mutate writer key nil :unset t
                                         :preconditions (owned-writer-preconditions writer)))))
          (slot-value writer 'retirement))
     (setf (slot-value writer 'stage) :retired)
     writer)))

(defun write-owned-writer-record (writer record)
  "Write a prepared intent or candidate once, then decode its exact readback."
  (let* ((kind (slot-value record 'kind)) (data (slot-value record 'data))
         (token (slot-value writer 'token))
         (revision (getf data (if (eq kind :pending) :writer :revision)))
         (writes (owned-record-writes record)))
  (owned-writer-call
   writer (ecase kind (:pending :retired) (:committed :pending))
   (lambda ()
     (unless (and (string= token revision)
                  (string= (getf data :workspace) (getf (slot-value (slot-value writer 'declaration) 'data) :id)))
       (fail-workspace "New bundle must belong to the current workspace writer"))
     (map nil (lambda (pair)
                (check-owned-writer-envelope writer (car pair) (cdr pair)
                                             (owned-writer-preconditions writer) :only-if-unset t)) writes)
     (map nil (lambda (pair)
                (owned-writer-mutate writer (car pair) (cdr pair) :only-if-unset t
                                     :preconditions (owned-writer-preconditions writer)))
          writes)
     (let ((observed (owned-writer-read writer (lambda (reader) (owned-read-bundle reader kind token)))))
       (unless (string= (slot-value observed 'json) (slot-value record 'json))
         (fail-workspace "Record readback differs from the prepared immutable bundle"))
       (setf (slot-value writer 'stage) (ecase kind (:pending :pending) (:committed :candidate)))
       observed)))))

(defun write-owned-writer-pending (writer)
  "Write the prepared intent before any domain operation."
  (write-owned-writer-record writer (slot-value writer 'pending)))

(defun publish-owned-writer (writer)
  "Publish once as the last writer mutation; post-publication work is read-only."
  (owned-writer-call
   writer :candidate
   (lambda ()
     (let* ((idle (make-owned-control :idle (slot-value writer 'token)))
            (outcome (owned-writer-mutate writer (slot-value writer 'control-key) idle
                                         :preconditions (owned-writer-preconditions writer))))
       (setf (slot-value writer 'control) idle (slot-value writer 'stage) :published)
       outcome))))

(defun perform-owned-domain-command (writer preconditions command &key required-type)
  "Invoke one trusted core-operation function with clamped options and retain its outcome.
PRECONDITIONS are fixed generated step predicates. This private boundary adds
the BUSY token and original context; full domain predicates belong to the executor."
  (owned-writer-call
   writer :pending
   (lambda ()
     (unless (and (functionp command)
                  (member required-type '(nil libtmux:session libtmux:window libtmux:pane libtmux:window-link)))
       (fail-workspace "Domain command requires a function and a registered result class"))
     (let* ((outer libtmux.internal::*dispatch-context-check*)
            (libtmux.internal::*dispatch-preconditions*
              (libtmux.internal::owned-dispatch-preconditions
               (append (libtmux.internal::owned-dispatch-preconditions libtmux.internal::*dispatch-preconditions*)
                       (owned-writer-preconditions writer)
                       (slot-value writer 'application-preconditions)
                       (libtmux.internal::owned-dispatch-preconditions preconditions))))
            (libtmux.internal::*dispatch-context-check*
              (lambda (client witness current)
                (when outer (funcall outer client witness current))
                (unless (eq client (slot-value writer 'client))
                  (error 'libtmux:stale-target :client client
                         :message "Workspace domain command used another client"))
                (owned-writer-check writer))))
       (unless (or (null outer) (functionp outer))
         (fail-workspace "Outer dispatch context check must be NIL or a function"))
       (let ((outcome (funcall command (owned-writer-options writer))))
         (unless (typep outcome 'libtmux:command-outcome)
           (error 'libtmux:incomplete-snapshot :message "Domain operation did not return a command outcome"))
         (owned-writer-retain writer (vector outcome))
         (libtmux.internal::check-outcome outcome)
         (when (libtmux:outcome-observation-error outcome)
           (error 'libtmux:incomplete-snapshot :outcome outcome
                  :cause (libtmux:outcome-observation-error outcome)
                  :message "Domain command succeeded but its observation failed"))
         (let ((value (when required-type (required-outcome-value outcome required-type "Domain command"))))
           (owned-writer-check writer)
           (setf (slot-value writer 'stage) :pending)
           (values outcome value)))))))
