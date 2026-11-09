(in-package #:libtmux.workspace)

(defun check-owned-inventory-key (namespace key)
  (let* ((suffix (subseq key (length namespace)))
         (parts (uiop:split-string suffix :separator ".")))
    (unless (equal parts '("control"))
      (unless (and (member (first parts) '("committed" "pending") :test #'string=)
                   (member (length parts) '(3 4)))
        (fail-workspace "Unknown key in the owned workspace namespace"))
      (owned-token (second parts) #(:inventory) (make-owned-context :native))
      (unless (or (and (= 3 (length parts)) (string= (third parts) "descriptor"))
                  (and (= 4 (length parts)) (string= (third parts) "chunk")
                       (let* ((text (fourth parts))
                              (index (and (<= 1 (length text) 3)
                                          (every #'libtmux.internal::ascii-digit-p text)
                                          (parse-integer text))))
                         (and index (<= index 511)
                              (string= text (format nil "~D" index))))))
        (fail-workspace "Noncanonical descriptor or chunk key in workspace inventory")))
    key))

(defun parse-owned-inventory (id text &key check-row invalid-key)
  "Read keys from already byte-bounded native printer output, without decoding values."
  (unless (and (stringp text) (plusp (length text)) (not (find #\Null text))
               (char= #\Newline (char text (1- (length text)))))
    (fail-workspace "Workspace inventory is not complete native printer text"))
  (let ((namespace (owned-namespace id)) (keys nil)
        (seen (make-hash-table :test #'equal)))
    (loop for start = 0 then (1+ end)
          for end = (position #\Newline text :start start)
          while end
          do (when check-row (funcall check-row))
             (when (loop for cursor from start below end
                         always (find (char text cursor) '(#\Space #\Tab)))
               (fail-workspace "Workspace inventory contains a blank native row"))
          when (and (<= (+ start (length namespace)) end)
                    (string= namespace text :start2 start :end2 (+ start (length namespace))))
            do (let* ((split (position-if (lambda (character) (find character '(#\Space #\Tab)))
                                         text :start start :end end))
                      (key (and split (subseq text start split))))
                 (unless key (fail-workspace "Workspace inventory row has no value boundary"))
                 (handler-case (check-owned-inventory-key namespace key)
                   (invalid-workspace (cause)
                     (if (and invalid-key (not (workspace-limit cause)))
                         (funcall invalid-key (copy-seq key) cause)
                         (error cause))))
                 (when (gethash key seen) (fail-workspace "Duplicate key in workspace inventory"))
                 (when (= (hash-table-count seen) 2048)
                   (fail-workspace "Workspace inventory exceeds 2048 keys" :limit :inventory-keys))
                 (setf (gethash key seen) t)
                 (push key keys)))
    (coerce (nreverse keys) 'simple-vector)))

(defun parse-owned-groups (text snapshot &key check-row)
  "Decode complete grouped-session facts; false is data, not a missing observation."
  (unless (and (stringp text) (not (find #\Null text))
               (or (zerop (length text)) (char= #\Newline (char text (1- (length text))))))
    (fail-workspace "Session-group facts are not complete native rows"))
  (let ((sessions (libtmux:sessions snapshot)) (facts nil)
        (seen (make-hash-table :test #'equal)))
    (loop for start = 0 then (1+ end)
          for end = (position #\Newline text :start start)
          while end
          do (when check-row (funcall check-row))
             (let ((parts (uiop:split-string (subseq text start end) :separator '(#\Tab))))
               (unless (and (= 3 (length parts)) (string= (first parts) "workspace-group/1")
                            (member (third parts) '("0" "1") :test #'string=)
                            (find (second parts) sessions :key #'libtmux:id :test #'string=))
                 (fail-workspace "Session-group facts disagree with the captured session set"))
               (owned-unique (second parts) seen #(:groups) "session-group row")
               (push (cons (copy-seq (second parts)) (string= (third parts) "1")) facts)))
    (unless (= (hash-table-count seen) (length sessions))
      (fail-workspace "Session-group facts do not cover every captured session"))
    (coerce (nreverse facts) 'simple-vector)))

(defun owned-graph-daemon (snapshot)
  (let ((provenance (libtmux:provenance snapshot)))
    (list :pid (getf provenance :server/pid) :start (getf provenance :server/start-time)
          :process-start (getf provenance :server/process-start)
          :device (getf provenance :server/socket-device) :inode (getf provenance :server/socket-inode)
          :version (getf provenance :server/version))))

(defun validate-owned-graph (record snapshot)
  "Validate live captured identities, retaining property drift for the local planner."
  (let* ((data (slot-value record 'data))
         (session-id (getf (getf data :session) :physical-id))
         (session (find session-id (libtmux:sessions snapshot) :key #'libtmux:id :test #'string=)))
    (unless (and (eq (slot-value record 'kind) :committed)
                 (equal (getf data :daemon) (owned-graph-daemon snapshot)) session)
      (fail-workspace "Owned session or daemon identity no longer matches" :type 'workspace-conflict))
    (let ((links (libtmux:window-links session)))
      (loop for mapped across (getf data :windows)
            for identity = (list session-id (getf mapped :index) (getf mapped :physical-id))
            for link = (find identity links :key #'libtmux:id :test #'equal)
            do (unless link
                 (fail-workspace "Owned window link is missing or points to another window"
                                 :type 'workspace-conflict))
               (let ((panes (libtmux:panes (libtmux:window link))))
                 (loop for pane across (getf mapped :panes)
                       unless (find (getf pane :physical-id) panes :key #'libtmux:id :test #'string=)
                         do (fail-workspace "Owned pane is missing or belongs to another window"
                                            :type 'workspace-conflict)))))
    t))

(defclass owned-state ()
  ((data :initarg :data) (snapshot :initarg :snapshot) (outcomes :initarg :outcomes))
  (:documentation "Private captured workspace metadata; acquisition alone never mutates tmux."))

(define-condition owned-state-error (workspace-error)
  ((control :initarg :control :initform nil)
   (inventory :initarg :inventory :initform #())
   (data :initarg :data :initform nil)
   (snapshot :initarg :snapshot :initform nil)
   (causes :initarg :causes :initform #())
   (outcomes :initarg :outcomes :initform #()))
  (:documentation "Owned metadata could not be established; acquired read evidence remains retained."))

(defun owned-state-data (state) (deep-copy (slot-value state 'data)))
(defun owned-state-snapshot (state) (slot-value state 'snapshot))
(defun owned-state-outcomes (state) (copy-seq (slot-value state 'outcomes)))
(defun owned-state-error-outcomes (condition) (copy-seq (slot-value condition 'outcomes)))
(defun owned-state-error-data (condition)
  "Return owned available evidence, which may span attempts and does not prove ready state."
  (deep-copy (slot-value condition 'data)))
(defun owned-state-error-snapshot (condition) (slot-value condition 'snapshot))
(defun owned-state-error-causes (condition) (copy-seq (slot-value condition 'causes)))

(defstruct owned-reader core declaration context generation witness row-counter
  snapshot control committed previous pending groups geometry failure (diagnostics nil)
  (headers nil) (status :incomplete) (attempt 0) (inventory #()))

(defun owned-reader-data (reader client start &optional declaration)
  (deep-copy
   (list :status (if reader (owned-reader-status reader) :incomplete)
         :context (symbol-name (if reader (owned-reader-context reader) (slot-value client 'libtmux::context)))
         :generation (if reader (owned-reader-generation reader) (slot-value client 'libtmux::generation))
         :witness (when reader (libtmux.internal::witness-provenance (owned-reader-witness reader)))
         :control (when reader (owned-reader-control reader))
         :declaration (let ((value (if reader (owned-reader-declaration reader) declaration)))
                        (when value (slot-value value 'data)))
         :committed (when (and reader (owned-reader-committed reader))
                      (slot-value (owned-reader-committed reader) 'data))
         :previous (when (and reader (owned-reader-previous reader))
                     (slot-value (owned-reader-previous reader) 'data))
         :pending (when (and reader (owned-reader-pending reader))
                    (slot-value (owned-reader-pending reader) 'data))
         :headers (if reader (coerce (reverse (owned-reader-headers reader)) 'simple-vector) #())
         :inventory (if reader (owned-reader-inventory reader) #())
         :groups (when reader (owned-reader-groups reader))
         :geometry (when reader (owned-reader-geometry reader))
         :read-restarts (if reader (owned-reader-attempt reader) 0)
         :acquired-start start :acquired-end (libtmux.internal::monotonic-seconds))))

(defun owned-reader-check (reader)
  (let* ((core (owned-reader-core reader))
         (client (libtmux.internal::configuration-reader-client core)))
    (libtmux.internal::configuration-reader-check core)
    (unless (and (eq (owned-reader-context reader) (slot-value client 'libtmux::context))
                 (= (owned-reader-generation reader) (slot-value client 'libtmux::generation))
                 (libtmux.internal::same-witness-p
                  (owned-reader-witness reader) (slot-value client 'libtmux::witness)))
      (error 'libtmux:stale-target :client client
             :message "Workspace acquisition changed client or daemon generation"))))

(defun owned-reader-charge-row (reader)
  (libtmux.internal::configuration-input-record (owned-reader-row-counter reader)))

(defun owned-read-leaf (reader name limit)
  (owned-reader-check reader)
  (multiple-value-bind (state value)
      (libtmux.internal::configuration-read-one
       (owned-reader-core reader) :option :server nil name :value-limit limit)
    (owned-reader-check reader)
    (case state
      (:missing (values nil nil))
      (:present
       (unless (stringp value) (fail-workspace "Owned metadata must be a scalar string"))
       (values value t))
      (otherwise (fail-workspace "Owned metadata is not a present scalar or a known absence")))))

(defun owned-read-control (reader)
  (let* ((id (getf (slot-value (owned-reader-declaration reader) 'data) :id))
         (value (owned-read-leaf reader (concatenate 'string (owned-namespace id) "control") 69)))
    (setf (owned-reader-control reader) value)))

(defun owned-read-text (reader arguments)
  (owned-reader-check reader)
  (let* ((core (owned-reader-core reader))
         (outcome
           (libtmux.internal::execute-capture-command
            (libtmux.internal::configuration-reader-client core)
            (libtmux.internal::check-command-envelope
             (libtmux.internal::guarded-read-command (owned-reader-witness reader) nil arguments))
            (libtmux.internal::configuration-reader-token core)
            (libtmux.internal::configuration-reader-budget core))))
    (libtmux.internal::interpret-read-outcome outcome)
    (owned-reader-check reader)
    (libtmux.internal::strict-text (libtmux:outcome-stdout outcome))))

(defun owned-read-inventory (reader &key invalid-key)
  (setf (owned-reader-inventory reader)
        (parse-owned-inventory
         (getf (slot-value (owned-reader-declaration reader) 'data) :id)
         (owned-read-text reader '("show-options" "-s" "-H"))
         :check-row (lambda () (owned-reader-charge-row reader)) :invalid-key invalid-key)))

(defun owned-read-bundle-parts (reader kind revision &optional reference on-header)
  "Return record, header and completeness; native failures still signal immediately."
  (let* ((id (getf (slot-value (owned-reader-declaration reader) 'data) :id))
         (descriptor (owned-read-leaf reader (owned-record-key id kind revision) 4096)))
    (unless descriptor (return-from owned-read-bundle-parts (values nil nil :absent)))
    (let* ((header (normalize-owned-descriptor (parse-owned-tree descriptor) (make-owned-context :json)))
           (count (getf header :chunks))
           (chunks (make-array count)))
      (push header (owned-reader-headers reader))
      (unless (and (eq kind (getf header :kind)) (string= revision (getf header :revision))
                   (or (null reference)
                       (every (lambda (key) (equal (getf reference key) (getf header key)))
                              '(:revision :bytes :chunks))))
        (fail-workspace "Workspace descriptor disagrees with its selected reference"))
      (when on-header (funcall on-header header))
      (loop for index below count
            for value = (owned-read-leaf reader (owned-record-key id kind revision index) 4096)
            do (unless value (return-from owned-read-bundle-parts (values nil header :incomplete)))
               (setf (aref chunks index) value))
      (values (decode-owned-record id kind revision descriptor chunks) header :complete))))

(defun owned-read-bundle (reader kind revision &optional reference)
  (multiple-value-bind (record header status)
      (owned-read-bundle-parts reader kind revision reference)
    (ecase status
      (:absent (fail-workspace "A referenced workspace descriptor is missing"))
      (:incomplete (fail-workspace "A referenced workspace chunk is missing"))
      (:complete (values record header)))))

(defun check-owned-inventory (reader bundles)
  (let* ((id (getf (slot-value (owned-reader-declaration reader) 'data) :id))
         (expected (make-hash-table :test #'equal))
         (inventory (owned-reader-inventory reader)))
    (setf (gethash (concatenate 'string (owned-namespace id) "control") expected) t)
    (dolist (header bundles)
      (let ((kind (getf header :kind)) (revision (getf header :revision)))
        (setf (gethash (owned-record-key id kind revision) expected) t)
        (dotimes (index (getf header :chunks))
          (setf (gethash (owned-record-key id kind revision index) expected) t))))
    (unless (and (= (length inventory) (hash-table-count expected))
                 (every (lambda (key) (gethash key expected)) inventory))
      (fail-workspace "Workspace inventory is incomplete or contains an unreferenced revision"))))

(defun owned-read-graph (reader)
  (let* ((core (owned-reader-core reader))
         (snapshot (libtmux.internal::capture-with-retries
                    (libtmux.internal::configuration-reader-client core)
                    (libtmux.internal::configuration-reader-token core)
                    (libtmux.internal::configuration-reader-budget core) 100000)))
    (setf (owned-reader-snapshot reader) snapshot
          (owned-reader-groups reader) nil
          (owned-reader-geometry reader) nil)
    (owned-reader-check reader)
    snapshot))

(defun owned-read-groups (reader snapshot)
  (setf (owned-reader-groups reader)
   (parse-owned-groups
   (if (zerop (length (libtmux:sessions snapshot))) ""
       (owned-read-text reader
                        (list "list-sessions" "-F"
                              (format nil "workspace-group/1~C#{session_id}~C#{session_grouped}" #\Tab #\Tab))))
   snapshot :check-row (lambda () (owned-reader-charge-row reader)))))

(defun owned-read-geometry (reader snapshot)
  (setf (owned-reader-geometry reader) nil)
  (let* ((version (libtmux.internal::server-witness-version (owned-reader-witness reader)))
         (format (owned-geometry-format version)))
    (setf (owned-reader-geometry reader)
          (parse-owned-geometry
           (if (zerop (length (libtmux:panes snapshot))) ""
               (owned-read-text reader (list "list-panes" "-a" "-F" format)))
           snapshot version :check-row (lambda () (owned-reader-charge-row reader))))))

(defun owned-read-attempts (reader start)
  (let* ((declaration (slot-value (owned-reader-declaration reader) 'data))
         (core (owned-reader-core reader)))
    (loop for attempt from 0 to 1
          for opening = (owned-read-control reader)
          for failure = nil
          for committed = nil for previous = nil for pending = nil for bundles = nil
          for snapshot = nil
          do (setf (owned-reader-attempt reader) attempt)
             (handler-case
                 (progn
                   (owned-read-inventory reader)
                   (if opening
                       (let ((control (parse-owned-control opening)))
                         (when (eq :busy (getf control :state))
                           (setf (owned-reader-status reader) :busy)
                           (error 'owned-state-error :message "Workspace has an incomplete or active writer"))
                         (multiple-value-bind (record header)
                             (owned-read-bundle reader :committed (getf control :head))
                           (setf committed record (owned-reader-committed reader) record) (push header bundles))
                         (let ((data (slot-value committed 'data)))
                           (when (getf data :previous)
                             (multiple-value-bind (record header)
                                 (owned-read-bundle reader :committed
                                                    (getf (getf data :previous) :revision) (getf data :previous))
                               (setf previous record (owned-reader-previous reader) record) (push header bundles)))
                           (multiple-value-bind (record header)
                               (owned-read-bundle reader :pending (getf control :head) (getf data :pending))
                             (setf pending record (owned-reader-pending reader) record) (push header bundles))
                           (let ((intent (slot-value pending 'data)))
                             (unless (and (string=
                                           (owned-json (encode-owned-declaration (getf intent :declaration)))
                                           (owned-json (encode-owned-declaration (getf data :declaration))))
                                          (equal (getf intent :base)
                                                 (if previous (getf (slot-value previous 'data) :revision) "0"))
                                          (or (null previous)
                                              (equal (getf data :daemon) (getf (slot-value previous 'data) :daemon))))
                               (fail-workspace "Committed workspace and pending intent references disagree"))))
                         (check-owned-inventory reader bundles))
                       (unless (zerop (length (owned-reader-inventory reader)))
                         (fail-workspace "Unclaimed workspace namespace contains orphan metadata")))
                   (setf snapshot (owned-read-graph reader))
                   (owned-read-groups reader snapshot)
                   (owned-read-geometry reader snapshot)
                   (if committed
                       (validate-owned-graph committed snapshot)
                       (when (find (getf (getf declaration :session) :name) (libtmux:sessions snapshot)
                                   :key #'libtmux:name :test #'string=)
                         (fail-workspace "An unowned session already uses the declared name"
                                         :type 'workspace-conflict)))
                   (owned-read-inventory reader)
                   (if committed (check-owned-inventory reader bundles)
                       (unless (zerop (length (owned-reader-inventory reader)))
                         (fail-workspace "Workspace namespace changed during vacancy acquisition"))))
               ((or invalid-workspace workspace-conflict) (condition)
                 (when (workspace-limit condition) (error condition))
                 (setf (owned-reader-failure reader) condition)
                 (push condition (owned-reader-diagnostics reader))
                 (setf failure condition)))
             (let ((closing (owned-read-control reader)))
               (owned-reader-check reader)
               (cond
                 ((not (equal opening closing))
                  (setf (owned-reader-failure reader) nil)
                  (when (= attempt 1)
                    (fail-workspace "Workspace control changed during both bounded read attempts")))
                 (failure (error failure))
                 (t
                  (setf (owned-reader-status reader) (if committed :owned :vacant)
                        (owned-reader-committed reader) committed
                        (owned-reader-previous reader) previous (owned-reader-pending reader) pending)
                  (return-from owned-read-attempts
                    (make-instance
                     'owned-state :snapshot snapshot
                     :outcomes (coerce (reverse (libtmux.internal::capture-budget-outcomes
                                               (libtmux.internal::configuration-reader-budget core))) 'simple-vector)
                     :data (owned-reader-data reader
                                              (libtmux.internal::configuration-reader-client core) start)))))))))

(defun call-with-owned-reader (client declaration cancel-token timeout output-limit record-limit procedure
                              &optional on-failure)
  (check-type client libtmux:client)
  (check-type declaration owned-declaration)
  (libtmux.internal::check-limits timeout output-limit)
  (unless (typep record-limit '(integer 1 100000))
    (fail-workspace "Workspace read record limit must be from 1 through 100000"))
  (libtmux.internal::call-with-operation
   client cancel-token
   (lambda (token)
     (let* ((start (libtmux.internal::monotonic-seconds))
            (budget (libtmux.internal::make-capture-budget
                     :start start :deadline (+ start timeout) :remaining output-limit
                     :row-limit 100000 :field-limit 1048576 :retain-outcomes t))
            (decode (libtmux.internal::make-configuration-decode-budget
                     :remaining-bytes output-limit :remaining-frames record-limit :remaining-records record-limit
                     :check (lambda () (libtmux.internal::check-capture-budget budget token))))
            (reader nil))
       (handler-case
           (progn
             (libtmux.internal::preflight-targets client nil token budget)
             (let* ((witness (slot-value client 'libtmux::witness))
                    (core (libtmux.internal::make-configuration-reader
                           :client client :token token :budget budget :decode decode :witness witness
                           :catalog (libtmux.internal::configuration-catalog
                                     (libtmux.internal::server-witness-version witness))))
                    (libtmux.internal::*command-socket-path* (libtmux.internal::server-witness-endpoint witness)))
               (setf reader (make-owned-reader :core core :declaration declaration :witness witness
                             :context (slot-value client 'libtmux::context)
                             :generation (slot-value client 'libtmux::generation)
                             :row-counter (libtmux.internal::make-configuration-input
                                           (libtmux.internal::octet-vector nil) 0 0 decode)))
               (funcall procedure reader start)))
         (error (cause)
           (let ((outcome (and (typep cause 'libtmux:libtmux-error) (libtmux:error-outcome cause))))
             (when (and outcome (not (member outcome (libtmux.internal::capture-budget-outcomes budget))))
               (libtmux.internal::charge-capture-outcome budget outcome))
             (let* ((primary (or (and reader (owned-reader-failure reader)) cause))
                    (causes (if reader (reverse (owned-reader-diagnostics reader)) nil)))
               (unless (member cause causes) (setf causes (append causes (list cause))))
               (if on-failure
                   (funcall on-failure reader primary cause causes budget start)
                   (error 'owned-state-error :client client :cause primary :outcome outcome
                      :control (and reader (copy-seq (owned-reader-control reader)))
                      :inventory (if reader (deep-copy (owned-reader-inventory reader)) #())
                      :data (owned-reader-data reader client start declaration)
                      :snapshot (and reader (owned-reader-snapshot reader))
                      :causes (coerce causes 'simple-vector)
                      :outcomes (coerce (reverse (libtmux.internal::capture-budget-outcomes budget)) 'simple-vector)
                      :message (format nil "Workspace state acquisition failed: ~A" primary)))))))))))

(defun fetch-owned-state (client declaration &key cancel-token
                                             (timeout (slot-value client 'libtmux::timeout))
                                             (output-limit (slot-value client 'libtmux::output-limit))
                                             (record-limit 100000))
  "Acquire private metadata and one graph under shared bounds; never adopt or mutate."
  (call-with-owned-reader client declaration cancel-token timeout output-limit record-limit #'owned-read-attempts))
