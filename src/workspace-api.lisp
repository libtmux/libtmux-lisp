(in-package #:libtmux.workspace)

(defun check-owned-workspace-limits (declaration max-windows max-panes max-argv max-environment)
  "Apply caller limits to already normalized owned data; protocol ceilings still apply."
  (let* ((data (slot-value declaration 'data)) (session (getf data :session))
         (windows (getf session :windows)) (panes 0))
    (flet ((limit (count maximum name path)
             (when (> count maximum)
               (fail-workspace "Owned workspace exceeds a configured limit" :path path :limit name))))
      (limit (length windows) max-windows :max-windows #(:session :windows))
      (limit (length (getf session :environment)) max-environment :max-environment #(:session :environment))
      (loop for window across windows for window-index from 0
            do (incf panes (length (getf window :panes)))
               (limit panes max-panes :max-panes #(:session :windows))
               (loop for pane across (getf window :panes) for pane-index from 0
                     do (limit (length (getf pane :command)) max-argv :max-argv
                               (vector :session :windows window-index :panes pane-index :command)))))))

(defun make-workspace (data &key (max-windows 100) (max-panes 1000) (max-argv 256) (max-environment 256))
  "Validate inert native DATA and return an owned WORKSPACE without I/O.
DATA is a finite keyword plist declaring libtmux.lisp.workspace/1 or /2.
Workspace/1 describes name-based topology reuse. Workspace/2 requires stable
IDs at the root, session, windows and panes; duplicate window names are allowed.
Mutable inputs are copied. Unknown/duplicate keys, cyclic containers and invalid
values signal INVALID-WORKSPACE with WORKSPACE-PATH and WORKSPACE-LIMIT.

MAX-WINDOWS, MAX-PANES, MAX-ARGV and MAX-ENVIRONMENT limit topology, individual
argv vectors and session environment pairs. Owned protocol ceilings remain in
force when a caller chooses larger limits. :COMMAND is literal argv;
:SHELL-COMMAND is explicit shell source. Cwd, environment and named/custom
layouts retain their creation meanings; changing existing processes is refused.

See also: WORKSPACE-DATA, PARSE-WORKSPACE, READ-WORKSPACE, PLAN-WORKSPACE,
APPLY-WORKSPACE, LIBTMUX:NEW-SESSION."
  (checked-limit max-windows :max-windows 1)
  (checked-limit max-panes :max-panes 1)
  (checked-limit max-argv :max-argv 0)
  (checked-limit max-environment :max-environment 0)
  (closed-plist data t #() "Workspace")
  (let ((schema (plist-value data :schema)))
    (cond
      ((and (stringp schema) (string= schema +schema+))
       (%make-v1-workspace data :max-windows max-windows :max-panes max-panes
                               :max-argv max-argv :max-environment max-environment))
      ((and (stringp schema) (string= schema "libtmux.lisp.workspace/2"))
       (let ((declaration (make-owned-declaration data)))
         (check-owned-workspace-limits declaration max-windows max-panes max-argv max-environment)
         (make-instance 'workspace :session nil :owned declaration :data (slot-value declaration 'data))))
      (t (fail-workspace "Unsupported or missing workspace :SCHEMA" :path #(:schema))))))

(defun workspace-document-path (path)
  "Translate registered native field names to JSON diagnostics without interning input."
  (map 'vector (lambda (part)
                 (if (keywordp part) (substitute #\_ #\- (string-downcase (symbol-name part))) part))
       path))

(defun parse-workspace
    (source &key (max-input-bytes +default-max-input-bytes+) (max-depth +default-max-depth+)
                 (max-nodes +default-max-nodes+) (max-string-length +default-max-string-length+)
                 (max-windows +default-max-windows+) (max-panes +default-max-panes+)
                 (max-argv +default-max-argv+) (max-environment +default-max-environment+)
                 (max-integer-digits +default-max-integer-digits+))
  "Parse one bounded workspace/1 or workspace/2 JSON string into a WORKSPACE.
The declared schema selects a closed grammar. Unknown/duplicate members,
invalid values and incomplete input fail; no external names are interned or
evaluated. Limits bound UTF-8 bytes, nesting, nodes, string length, topology,
argv length, session environment pairs and integer token digits. Owned protocol
ceilings remain in force when callers choose larger limits.

Workspace/2 requires stable IDs and permits repeated window names. Command
arrays are literal argv; shell_command is explicit source. Named/custom layouts
and all other creation inputs have the same meanings as MAKE-WORKSPACE.
Retained strings and containers are owned. Signals INVALID-WORKSPACE-DOCUMENT
or WORKSPACE-LIMIT-EXCEEDED with WORKSPACE-PATH and WORKSPACE-LIMIT. No tmux I/O.

See also: MAKE-WORKSPACE, READ-WORKSPACE, WORKSPACE-DATA."
  (unless (stringp source) (fail-document "PARSE-WORKSPACE requires a complete JSON string"))
  (checked-limit max-input-bytes :max-input-bytes 1)
  (checked-limit max-depth :max-depth 1)
  (checked-limit max-nodes :max-nodes 1)
  (checked-limit max-string-length :max-string-length 1)
  (checked-limit max-windows :max-windows 1)
  (checked-limit max-panes :max-panes 1)
  (checked-limit max-argv :max-argv 0)
  (checked-limit max-environment :max-environment 0)
  (checked-limit max-integer-digits :max-integer-digits 0)
  (bounded-utf-8-size source max-input-bytes)
  (validate-json-integers source max-integer-digits)
  (let* ((document (parse-json-events source max-depth max-nodes max-string-length))
         (schema (required-member document "schema" #())))
    (cond
      ((and (stringp schema) (string= schema +schema+))
       (workspace-from-v1-document document max-windows max-panes max-argv max-environment))
      ((and (stringp schema) (string= schema "libtmux.lisp.workspace/2"))
       (bounded-utf-8-size source +owned-record-bytes+)
       (validate-json-integers source (min 32 max-integer-digits))
       (let ((tree (if (or (> max-depth 32) (> max-nodes +owned-record-nodes+)
                           (> max-string-length +owned-text-length+))
                       (parse-json-events source (min 32 max-depth) (min +owned-record-nodes+ max-nodes)
                                                 (min +owned-text-length+ max-string-length))
                       document)))
         (handler-case
             (let* ((data (normalize-owned-declaration tree (make-owned-context :json)))
                    (declaration (make-owned-declaration data)))
               (check-owned-workspace-limits declaration max-windows max-panes max-argv max-environment)
               (make-instance 'workspace :session nil :owned declaration :data (slot-value declaration 'data)))
           (invalid-workspace-document (condition) (error condition))
           (invalid-workspace (condition)
             (fail-document "Owned document violates its workspace contract" :cause condition
                            :path (workspace-document-path (workspace-path condition))
                            :limit (workspace-limit condition))))))
      (t (fail-document "Unsupported workspace-document schema" :path #("schema"))))))

(defclass workspace-state ()
  ((value :initarg :value))
  (:documentation "Captured ready/vacant owned workspace evidence for local planning.
Acquire through FETCH-WORKSPACE-STATE. Readers remain usable after client close.

See also: STATE-DATA, STATE-SNAPSHOT, PLAN-WORKSPACE, WORKSPACE-INSPECTION."))

(define-condition workspace-state-error (workspace-error)
  ((data :initarg :data :initform nil) (snapshot :initarg :snapshot :initform nil)
   (outcomes :initarg :outcomes :initform #()) (causes :initarg :causes :initform #()))
  (:documentation "Owned state acquisition failed with retained partial read evidence.
Failure does not imply vacancy or grant ownership. Inspect STATE-DATA,
STATE-SNAPSHOT, STATE-OUTCOMES and STATE-CAUSES without further I/O.

See also: FETCH-WORKSPACE-STATE, INSPECT-WORKSPACE, LIBTMUX:ERROR-CAUSE."))

(defclass workspace-inspection ()
  ((value :initarg :value))
  (:documentation "Explicit read evidence, including incomplete or invalid owned work.
An inspection cannot stand in for WORKSPACE-STATE in local planning.

See also: INSPECT-WORKSPACE, INSPECTION-DATA, WORKSPACE-INSPECTION-ERROR."))

(define-condition workspace-inspection-error (workspace-error)
  ((inspection :initarg :inspection) (terminal :initarg :terminal))
  (:documentation "Inspection stopped with its original and terminal failures retained.
INSPECTION-EVIDENCE returns the partial public observation. Its causes remain
separate from INSPECTION-TERMINAL; neither admits planning or mutation.

See also: INSPECTION-EVIDENCE, INSPECTION-TERMINAL, INSPECTION-CAUSES."))

(defgeneric state-data (state)
  (:documentation "Return fresh finite metadata for WORKSPACE-STATE or WORKSPACE-STATE-ERROR.
No I/O. Partial metadata from an error does not prove readiness or vacancy.

See also: STATE-SNAPSHOT, STATE-OUTCOMES, STATE-CAUSES."))
(defgeneric state-snapshot (state)
  (:documentation "Return STATE's retained captured SNAPSHOT, or NIL before capture. No I/O.

See also: STATE-DATA, FETCH-WORKSPACE-STATE, LIBTMUX:PANES."))
(defgeneric state-outcomes (state)
  (:documentation "Return STATE's read COMMAND-OUTCOME objects in a fresh simple vector.
Includes retained unsuccessful reads. No I/O.

See also: STATE-CAUSES, LIBTMUX:OUTCOME-STATUS."))
(defgeneric state-causes (state)
  (:documentation "Return retained acquisition conditions in a fresh simple vector. No I/O.
Successful state has an empty vector. Original condition objects are shared.

See also: WORKSPACE-STATE-ERROR, LIBTMUX:ERROR-CAUSE."))
(defgeneric inspection-data (inspection)
  (:documentation "Return fresh attempts, record roles and diagnostics from INSPECTION. No I/O.
Read completion does not establish valid ownership or application success.

See also: INSPECTION-SNAPSHOTS, INSPECTION-CAUSES, INSPECT-WORKSPACE."))
(defgeneric inspection-snapshots (inspection)
  (:documentation "Return retained captured SNAPSHOT objects in a fresh simple vector. No I/O.
Each capture remains paired with its attempt's metadata in INSPECTION-DATA.

See also: INSPECTION-DATA, INSPECTION-OUTCOMES."))
(defgeneric inspection-outcomes (inspection)
  (:documentation "Return INSPECTION's read outcomes in a fresh simple vector. No I/O.

See also: INSPECTION-DATA, LIBTMUX:OUTCOME-STATUS."))
(defgeneric inspection-causes (inspection)
  (:documentation "Return original retained conditions in a fresh simple vector. No I/O.

See also: INSPECTION-DATA, INSPECTION-TERMINAL, LIBTMUX:ERROR-CAUSE."))
(defgeneric inspection-evidence (condition)
  (:documentation "Return the partial WORKSPACE-INSPECTION retained by CONDITION. No I/O.

See also: WORKSPACE-INSPECTION-ERROR, INSPECTION-DATA, INSPECTION-TERMINAL."))
(defgeneric inspection-terminal (condition)
  (:documentation "Return the terminal condition that stopped inspection. No I/O.
The original metadata cause remains in the cause chain and inspection evidence.

See also: INSPECTION-EVIDENCE, INSPECTION-CAUSES, LIBTMUX:ERROR-CAUSE."))
(defgeneric plan-data (plan)
  (:documentation "Return (values fresh-owned-data T), or (values NIL NIL) for legacy evidence.
Accepts WORKSPACE-PLAN or WORKSPACE-CONFLICT. Owned data separates declaration
changes, captured drift, informational context, conflicts and :PUBLISH-P.
An empty step vector can still require metadata publication. No I/O.

See also: PLAN-STEPS, PLAN-WORKSPACE, WORKSPACE-CONFLICT."))
(defgeneric result-data (result)
  (:documentation "Return owned application data and presence as two values, without I/O.
Accepts WORKSPACE-RESULT or WORKSPACE-APPLY-FAILED. Returns fresh data and T for
owned evidence; legacy evidence returns NIL,NIL. Data distinguishes phase,
mappings, selected/candidate/observed metadata and publication status.

See also: RESULT-SNAPSHOT, RESULT-OUTCOMES, RESULT-CAUSES, FAILED-STEP."))
(defgeneric result-causes (result)
  (:documentation "Return retained application conditions in a fresh simple vector. No I/O.
Conditions keep primary-first order and identity deduplication; successful
applications without failures return an empty vector.

See also: RESULT-DATA, WORKSPACE-APPLY-FAILED, LIBTMUX:ERROR-CAUSE."))

(defmethod state-data ((state workspace-state)) (owned-state-data (slot-value state 'value)))
(defmethod state-snapshot ((state workspace-state)) (owned-state-snapshot (slot-value state 'value)))
(defmethod state-outcomes ((state workspace-state)) (owned-state-outcomes (slot-value state 'value)))
(defmethod state-causes ((state workspace-state)) (make-array 0))
(defmethod state-data ((condition workspace-state-error)) (deep-copy (slot-value condition 'data)))
(defmethod state-snapshot ((condition workspace-state-error)) (slot-value condition 'snapshot))
(defmethod state-outcomes ((condition workspace-state-error)) (copy-seq (slot-value condition 'outcomes)))
(defmethod state-causes ((condition workspace-state-error)) (copy-seq (slot-value condition 'causes)))
(defmethod inspection-data ((value workspace-inspection)) (owned-inspection-data (slot-value value 'value)))
(defmethod inspection-snapshots ((value workspace-inspection)) (owned-inspection-snapshots (slot-value value 'value)))
(defmethod inspection-outcomes ((value workspace-inspection)) (owned-inspection-outcomes (slot-value value 'value)))
(defmethod inspection-causes ((value workspace-inspection)) (owned-inspection-causes (slot-value value 'value)))
(defmethod inspection-evidence ((condition workspace-inspection-error)) (slot-value condition 'inspection))
(defmethod inspection-terminal ((condition workspace-inspection-error)) (slot-value condition 'terminal))
(defmethod plan-data ((value workspace-plan))
  (let ((data (slot-value value 'data))) (values (deep-copy data) (not (null data)))))
(defmethod plan-data ((condition workspace-conflict))
  (let ((data (slot-value condition 'data))) (values (deep-copy data) (not (null data)))))
(defmethod result-data ((value workspace-result))
  (let ((data (slot-value value 'data))) (values (deep-copy data) (not (null data)))))
(defmethod result-data ((condition workspace-apply-failed))
  (let ((data (slot-value condition 'data))) (values (deep-copy data) (not (null data)))))
(defmethod result-snapshot ((condition workspace-apply-failed)) (slot-value condition 'snapshot))
(defmethod result-causes ((value workspace-result)) (copy-seq (slot-value value 'causes)))
(defmethod result-causes ((condition workspace-apply-failed)) (copy-seq (slot-value condition 'causes)))

(defun require-owned-workspace (workspace)
  (check-type workspace workspace)
  (or (slot-value workspace 'owned)
      (fail-workspace "This operation requires workspace/2" :path #(:schema))))

(defun plan-workspace (workspace &optional observation &key reconcile)
  "Return a local WORKSPACE-PLAN for WORKSPACE and captured OBSERVATION.
Workspace/1 accepts a SNAPSHOT or no observation for a creation preview; an
exact captured topology produces no steps. Workspace/2 requires an explicitly
acquired WORKSPACE-STATE for the same workspace ID. A snapshot or incomplete
inspection cannot establish ownership. Matching acquired state remains usable
after its client closes. No acquisition, refresh or mutation occurs.

Owned planning separates declaration changes and captured drift. By default,
either requires explicit :RECONCILE before a plan can be returned; unsupported
changes remain conflicts. PLAN-DATA exposes diagnostics on a plan or
WORKSPACE-CONFLICT. An empty owned step vector can still require metadata
publication: inspect :PUBLISH-P. Application always reacquires and replans.
Non-NIL RECONCILE is invalid for workspace/1.

See also: FETCH-WORKSPACE-STATE, PLAN-DATA, PLAN-STEPS, APPLY-WORKSPACE,
WORKSPACE-STATE, WORKSPACE-CONFLICT."
  (check-type workspace workspace)
  (let ((declaration (slot-value workspace 'owned)))
    (unless declaration
      (when reconcile (fail-workspace "Reconciliation requires workspace/2" :path #(:schema)))
      (return-from plan-workspace (%plan-v1-workspace workspace observation)))
    (unless (typep observation 'workspace-state)
      (fail-workspace "Owned planning requires an explicitly acquired WORKSPACE-STATE" :type 'workspace-conflict))
    (let* ((state (slot-value observation 'value))
           (data (slot-value state 'data)))
      (unless (equal (getf (slot-value declaration 'data) :id) (getf (getf data :declaration) :id))
        (fail-workspace "Planning state belongs to a different workspace ID" :path #(:id) :type 'workspace-conflict))
      (handler-case
          (let ((plan (plan-owned-workspace declaration state :reconcile reconcile)))
            (make-instance 'workspace-plan :steps (owned-plan-steps plan) :data (owned-plan-data plan)))
        (owned-plan-conflict (condition)
          (error 'workspace-conflict :cause condition :data (owned-plan-error-data condition)
                 :path (workspace-path condition) :limit (workspace-limit condition)
                 :message (libtmux:error-message condition)))))))

(defun fetch-workspace-state (client workspace &key cancel-token
                             (timeout (slot-value client 'libtmux::timeout))
                             (output-limit (slot-value client 'libtmux::output-limit)) (record-limit 100000))
  "Acquire ready/vacant owned metadata and a captured graph explicitly through CLIENT.
WORKSPACE must use schema /2; /1 is refused before I/O. TIMEOUT and OUTPUT-LIMIT
share the bounded read policy across attempts. RECORD-LIMIT is an integer from
1 through 100000; CANCEL-TOKEN is shared. No mutation occurs. Returns a
WORKSPACE-STATE for local planning, usable after client close. Actual read
failures signal WORKSPACE-STATE-ERROR with partial evidence; invalid arguments
remain validation failures. Failure is never reported as vacancy.

See also: STATE-DATA, STATE-SNAPSHOT, STATE-OUTCOMES, STATE-CAUSES,
INSPECT-WORKSPACE, PLAN-WORKSPACE."
  (let ((declaration (require-owned-workspace workspace)))
    (handler-case
        (make-instance 'workspace-state
                       :value (fetch-owned-state client declaration :cancel-token cancel-token
                                                 :timeout timeout :output-limit output-limit :record-limit record-limit))
      (owned-state-error (condition)
        (error 'workspace-state-error :client client :cause condition :outcome (libtmux:error-outcome condition)
               :path (workspace-path condition) :limit (workspace-limit condition)
               :data (owned-state-error-data condition) :snapshot (owned-state-error-snapshot condition)
               :outcomes (owned-state-error-outcomes condition) :causes (owned-state-error-causes condition)
               :message "Owned state acquisition failed; inspect its retained read evidence")))))

(defun inspect-workspace (client workspace &key cancel-token (timeout (slot-value client 'libtmux::timeout))
                         (output-limit (slot-value client 'libtmux::output-limit)) (record-limit 100000))
  "Acquire explicit incomplete-workspace evidence through CLIENT without mutation.
WORKSPACE must use schema /2; /1 is refused before I/O. Read limits and
CANCEL-TOKEN have FETCH-WORKSPACE-STATE's meanings. Returns a distinct
WORKSPACE-INSPECTION, never a planning input. Completed inspection can describe
BUSY or invalid ownership. A terminal failure signals WORKSPACE-INSPECTION-ERROR
with a partial inspection and original/terminal causes separately retained.

See also: INSPECTION-DATA, INSPECTION-SNAPSHOTS, INSPECTION-OUTCOMES,
INSPECTION-CAUSES, INSPECTION-EVIDENCE, INSPECTION-TERMINAL."
  (let ((declaration (require-owned-workspace workspace)))
    (handler-case
        (make-instance 'workspace-inspection
                       :value (inspect-owned-state client declaration :cancel-token cancel-token
                                                   :timeout timeout :output-limit output-limit :record-limit record-limit))
      (owned-inspection-error (condition)
        (error 'workspace-inspection-error :client client :cause condition
               :outcome (libtmux:error-outcome condition)
               :inspection (make-instance 'workspace-inspection :value (owned-inspection-error-evidence condition))
               :terminal (owned-inspection-error-terminal condition)
               :message "Owned inspection stopped; inspect its retained attempts and causes")))))

(defun retained-workspace-causes (condition)
  "Keep the cause chain and additional read failures once, without traversing cycles."
  (let ((seen (make-hash-table :test #'eq)) (result nil))
    (labels ((visit (value)
               (when (and (typep value 'condition) (not (gethash value seen)))
                 (setf (gethash value seen) t)
                 (push value result)
                 (when (typep value 'libtmux:libtmux-error) (visit (libtmux:error-cause value)))
                 (typecase value
                   (owned-state-error (map nil #'visit (owned-state-error-causes value)))
                   (owned-inspection-error
                    (map nil #'visit (owned-inspection-causes (owned-inspection-error-evidence value))))))))
      (visit condition))
    (coerce (nreverse result) 'simple-vector)))

(defun retained-workspace-snapshot (condition causes)
  (or (owned-apply-error-snapshot condition)
      (some (lambda (cause)
              (when (typep cause 'owned-state-error) (owned-state-error-snapshot cause))) causes)))

(defun apply-workspace
    (client workspace &key cancel-token (timeout nil timeout-p) (output-limit nil output-limit-p)
                          (total-timeout nil total-timeout-p) reconcile)
  "Apply WORKSPACE through explicit CLIENT and return a WORKSPACE-RESULT.
Workspace/1 retains topology-only creation/reuse. Workspace/2 freshly acquires
owned state and replans; a preview is never mutation authority. By default
owned declaration changes or drift are refused; :RECONCILE permits only the
qualified additive, rename, metadata and layout changes. It never adopts an
unowned session or repeats an uncertain mutation. RECONCILE requires schema /2.

TIMEOUT and OUTPUT-LIMIT apply per core operation; CANCEL-TOKEN is shared.
TOTAL-TIMEOUT, when supplied, is a nonnegative finite number of seconds shared
across acquisition, planning and application. It controls admission, including
no-op planning, and is not a hard caller wall-time bound. Synchronous setup and
cleanup can extend an admitted call. Invalid arguments fail before application.

Owned results retain read outcomes even for no-mutation reapplication.
RESULT-DATA separates selected/candidate/observed metadata and publication
status; RESULT-CREATED-P reports creation of the owned session. Conditional
publication is the final mutation, and later observation is read-only.

Owned acquisition, planning and execution failures signal WORKSPACE-APPLY-FAILED
with local RESULT-DATA, RESULT-SNAPSHOT, RESULT-OUTCOMES and RESULT-CAUSES.
FAILED-STEP retains the actual step where known. Successful publication with
failed observation remains distinguishable from failed/uncertain publication.
Legacy failures retain their original early-validation and partial-outcome
behavior. No rollback, hidden refresh during inspection or automatic retry.

See also: PLAN-WORKSPACE, FETCH-WORKSPACE-STATE, RESULT-DATA, RESULT-SNAPSHOT,
RESULT-OUTCOMES, RESULT-CAUSES, FAILED-STEP, WORKSPACE-DEADLINE-EXCEEDED."
  (check-type client libtmux:client)
  (check-type workspace workspace)
  (let* ((declaration (slot-value workspace 'owned))
         (options (append (operation-options cancel-token timeout timeout-p output-limit output-limit-p)
                          (when total-timeout-p (list :total-timeout total-timeout)))))
    (unless declaration
      (when reconcile (fail-workspace "Reconciliation requires workspace/2" :path #(:schema)))
      (return-from apply-workspace (apply #'%apply-v1-workspace client workspace options)))
    (when total-timeout-p
      (libtmux.internal::check-limits total-timeout
                                     (if output-limit-p output-limit (slot-value client 'libtmux::output-limit))))
    (handler-case
        (let* ((result (apply #'apply-owned-workspace client declaration :reconcile reconcile options))
               (data (owned-result-data result)))
          (make-instance 'workspace-result :snapshot (owned-result-snapshot result)
                         :outcomes (owned-result-outcomes result) :data data
                         :created-p (eq :vacant (getf (getf data :selected-state) :status))))
      (owned-apply-error (condition)
        (let ((causes (retained-workspace-causes condition)))
          (error 'workspace-apply-failed :client client :cause condition
                 :outcome (libtmux:error-outcome condition) :step (owned-apply-error-step condition)
                 :data (owned-apply-error-data condition) :outcomes (owned-apply-error-outcomes condition)
                 :snapshot (retained-workspace-snapshot condition causes) :causes causes
                 :path (workspace-path condition) :limit (workspace-limit condition)
                 :message "Owned workspace application stopped; inspect its public phase, mappings and outcomes"))))))
