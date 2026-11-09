(in-package #:libtmux.internal)

(defun owned-configuration-names (names &key environment)
  "Copy at most 4096 finite whole names; never intern supplied text."
  (cond ((and (vectorp names) (not (stringp names)))
         (when (> (length names) 4096) (invalid-argument "At most 4096 configuration names are allowed")))
        ((listp names)
         (loop for tail = names then (cdr tail) for count from 0
               while tail
               do (unless (and (consp tail) (< count 4096))
                    (invalid-argument "Configuration names must be a finite list of at most 4096 names"))))
        (t (invalid-argument "Configuration names must be a list or vector")))
  (map 'simple-vector
       (lambda (name)
         (unless (and (stringp name) (<= 1 (length name) 1048576))
           (invalid-argument "Configuration names must be nonempty bounded strings"))
         (let ((name (text-argument name "Configuration name" nil)))
           (when (find (if environment #\= #\[) name)
             (invalid-argument (if environment "Environment names cannot contain ="
                                  "Whole option names cannot contain [ element syntax")))
           (when (> (length (encode-utf8 name)) 1048576)
             (invalid-argument "Configuration name exceeds its UTF-8 byte limit"))
           name))
       names))

(defun ordinary-configuration-input (bytes failed stamp budget)
  "Append an internal codec boundary; charge only acquired bytes to its ledger."
  (let ((tail (encode-utf8 (format nil "%~A ~D 0 0~%" (if failed "error" "end") stamp))))
    (incf (configuration-decode-budget-remaining-bytes budget) (length tail))
    (concatenate '(vector (unsigned-byte 8)) bytes tail)))

(defun decode-ordinary-option (bytes catalog name scope &key failed hooks-only
                               (budget (make-configuration-decode-budget))
                               (value-limit 1048576))
  "Decode one complete ordinary payload; the appended token is not a server frame."
  (let ((wire (ordinary-configuration-input bytes failed 0 budget)))
    (multiple-value-bind (state value offset)
        (decode-configuration-option-leaf wire catalog name scope 0 0
          :hooks-only hooks-only :budget budget :value-limit value-limit)
      (unless (= offset (length wire)) (malformed-configuration))
      (values state value))))

(defun decode-ordinary-environment (bytes name &key failed (profile :direct)
                                    (budget (make-configuration-decode-budget))
                                    (value-limit 1048576))
  "Decode a complete ordinary environment payload without a name/end collision."
  (let* ((name (encode-utf8 name))
         (check (make-configuration-input (octet-vector nil) 0 0 budget))
         (stamp (if (configuration-name-overlaps-end-p check name profile (format nil "%end 0 0 0~%")) 1 0))
         (wire (ordinary-configuration-input bytes failed stamp budget)))
    (multiple-value-bind (state value offset)
        (decode-configuration-environment-leaf wire name stamp 0
          :profile profile :budget budget :value-limit value-limit)
      (unless (= offset (length wire)) (malformed-configuration))
      (values state value))))

(defstruct configuration-reader
  client token budget decode catalog witness relation active-name active-scope current-outcome
  (outcomes nil) (records nil))

(defparameter *configuration-option-format*
  (format nil "libtmux-option/1~C#{q/a:option_name}~C#{q/a:option_array_key}~C#{option_has_array_key}~C#{option_has_value}~C#{option_is_parent}~C#{option_is_array}~C#{option_is_string}~C#{option_is_hook}~C#{option_is_user}~C#{q/a:option_value}"
          #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab))

(defun configuration-reader-check (reader)
  (check-capture-budget (configuration-reader-budget reader) (configuration-reader-token reader)))

(defun configuration-read-one (reader domain scope target name &key hidden hooks-only value-limit)
  "Acquire a known ordinary leaf under the shared owner, retaining its outcome."
  (setf (configuration-reader-active-name reader) name
        (configuration-reader-active-scope reader) scope
        (configuration-reader-current-outcome reader) nil)
  (configuration-reader-check reader)
  (multiple-value-bind (targets flags)
      (if (eq domain :environment) (environment-scope-data scope target)
          (configuration-scope-data scope target))
    (let* ((catalog (configuration-reader-catalog reader))
           (arguments
             (append (list (if (eq domain :environment) "show-environment"
                              (if hooks-only "show-hooks" "show-options"))) flags
                     (when (eq domain :environment) '("-s")) (when hidden '("-h"))
                     (when (and (eq domain :option) (option-catalog-formatted-p catalog))
                       (list "-F" *configuration-option-format*))
                     (list "--" (literal-format name))))
           (relation (configuration-reader-relation reader)))
      (when relation
        (destructuring-bind (pane window) relation
          (setf arguments (list "if-shell" "-F" "-t" (libtmux:id pane)
                                (format-equal "window_id" (libtmux:id window))
                                (tmux-command-text arguments) "libtmux-internal-read-target-refused"))))
      (let* ((budget (configuration-reader-budget reader))
             (remaining (capture-budget-remaining budget))
             (encoded (check-command-envelope
                       (guarded-read-command (configuration-reader-witness reader) targets arguments)))
             (outcome (progn
                        (unless (plusp remaining)
                          (error 'libtmux:output-limit-exceeded :message "Configuration acquisition exhausted its byte budget"))
                        (execute-tmux (configuration-reader-client reader) encoded
                        (configuration-reader-token reader)
                        (max 0 (- (capture-budget-deadline budget) (monotonic-seconds)))
                        remaining nil)))
             (stdout (slot-value outcome 'libtmux::stdout))
             (stderr (slot-value outcome 'libtmux::stderr))
             (finished (and (eq (libtmux:outcome-phase outcome) :exited)
                            (member (libtmux:outcome-status outcome) '(:succeeded :failed))
                            (member (libtmux:outcome-exit-code outcome) '(0 1))
                            (null (libtmux:outcome-reason outcome))))
             (missing (and finished (= 1 (libtmux:outcome-exit-code outcome))
                           (zerop (length stdout))
                           (equalp stderr (encode-utf8
                                          (format nil "~A~A~%" (if (eq domain :environment)
                                                                  "unknown variable: " "invalid option: ") name))))))
        (push outcome (configuration-reader-outcomes reader))
        (setf (configuration-reader-current-outcome reader) outcome)
        (decf (capture-budget-remaining budget) (+ (length stdout) (length stderr)))
        (unless (and finished (or missing (plusp (length stdout))
                                 (and (eq (libtmux:outcome-status outcome) :succeeded) (zerop (length stderr)))))
          (check-outcome outcome)
          (error 'libtmux:command-failed :outcome outcome :message "Configuration read produced unexpected diagnostics"))
        (multiple-value-bind (state value)
            (let ((bytes (if missing stderr stdout)))
              (if (eq domain :environment)
                  (decode-ordinary-environment bytes name :failed missing
                    :profile (configuration-option-profile catalog) :budget (configuration-reader-decode reader)
                    :value-limit value-limit)
                  (decode-ordinary-option bytes catalog name scope :failed missing :hooks-only hooks-only
                    :budget (configuration-reader-decode reader) :value-limit value-limit)))
          (setf (slot-value outcome 'libtmux::value)
                (owned-data (append (list :name name :scope scope :target-id (and target (libtmux:id target))
                                         :state state :value value)
                                    (when (eq domain :environment) (list :hidden-p hidden))))
                (slot-value outcome 'libtmux::present-p) t)
          (unless missing
            (check-outcome outcome)
            (when (plusp (length stderr))
              (error 'libtmux:command-failed :outcome outcome :message "Configuration read produced unexpected diagnostics")))
          (values state value))))))

(defun configuration-layers (scope target inherited)
  (let ((local (list scope target)))
    (cons local
          (when inherited
            (case scope
              (:session (list (list :global-session nil)))
              (:window (list (list :global-window nil)))
              (:pane (list (list :window (libtmux:window target)) (list :global-window nil))))))))

(defun configuration-option-record (reader scope target spec inherited hooks-only value-limit)
  (let* ((name (option-spec-name spec))
         (layers (configuration-layers scope target inherited)))
    (loop repeat 3
          do (setf (configuration-reader-relation reader) nil)
             (let ((shadowed nil) (source nil) (value nil) (changed nil))
               (loop for tail on layers for (table entity) = (car tail)
                     do (when (and (eq scope :pane) (not (eq table :pane)))
                          (setf (configuration-reader-relation reader) (list target (libtmux:window target))))
                        (multiple-value-bind (state observed)
                            (configuration-read-one reader :option table entity name :hooks-only hooks-only :value-limit value-limit)
                          (when (eq state :present) (setf source (car tail) value observed) (return))
                          (when (cdr tail) (push (car tail) shadowed))))
               (dolist (layer (reverse shadowed))
                 (when (eq :present (configuration-read-one reader :option (first layer) (second layer) name
                                    :hooks-only hooks-only :value-limit value-limit))
                   (setf changed t)))
               (unless changed
                 (return-from configuration-option-record
                   (list :name (copy-seq name) :scope scope :target-id (and target (libtmux:id target))
                         :version (copy-seq (option-catalog-version (configuration-reader-catalog reader)))
                         :type (option-spec-kind spec) :array-p (not (null (option-spec-array-p spec)))
                         :present-p (not (null source)) :value value :source-scope (first source)
                         :source-target-id (and (second source) (libtmux:id (second source)))
                         :inherited-p (and source (not (eq (first source) scope)))))))
          finally (error 'libtmux:incomplete-snapshot :message "Configuration inheritance changed during acquisition"))))

(defun configuration-environment-record (reader scope target name value-limit)
  (loop repeat 3
        do (multiple-value-bind (state value)
               (configuration-read-one reader :environment scope target name :value-limit value-limit)
             (let ((hidden nil))
               (when (eq state :empty)
                 (setf hidden t)
                 (multiple-value-setq (state value)
                   (configuration-read-one reader :environment scope target name :hidden t :value-limit value-limit)))
               (when (or (member state '(:present :removed)) (and (eq state :missing) (not hidden)))
                 (return-from configuration-environment-record
                   (append (list :name (copy-seq name) :scope scope :target-id (and target (libtmux:id target))
                                 :version (copy-seq (option-catalog-version (configuration-reader-catalog reader)))
                                 :state (if (eq state :missing) :absent state) :value value)
                           (unless (eq state :missing) (list :hidden-p hidden)))))))
        finally (error 'libtmux:incomplete-snapshot :message "Environment visibility changed during acquisition")))

(defun acquire-configuration (client domain scope target names names-p inherited hooks-only
                             cancel-token timeout output-limit record-limit value-limit &key key key-p)
  (check-type client libtmux:client)
  (if (eq domain :environment) (environment-scope-data scope target)
      (progn
        (when (and hooks-only (eq scope :server)) (invalid-argument "Hooks have no server table"))
        (configuration-scope-data scope target)))
  (unless (and (typep record-limit '(integer 1 100000)) (typep value-limit '(integer 0 1048576)))
    (invalid-argument "Configuration limits require 1..100000 records and 0..1048576 value bytes"))
  (when (and (eq domain :environment) (not names-p))
    (invalid-argument "Decoded environment reads require explicit :names"))
  (when names-p (setf names (owned-configuration-names names :environment (eq domain :environment))))
  (when key-p
    (unless (or (integerp key) (and (stringp key) (<= 1 (length key) 1048576)))
      (invalid-argument "Array key must be an integer or nonempty bounded string"))
    (when (stringp key)
      (setf key (text-argument key "Array key" nil))
      (when (> (length (encode-utf8 key)) 1048576)
        (invalid-argument "Array key exceeds its UTF-8 byte limit"))))
  (when cancel-token (check-type cancel-token libtmux:cancellation-token))
  (setf timeout (or timeout (slot-value client 'libtmux::timeout))
        output-limit (or output-limit (slot-value client 'libtmux::output-limit)))
  (check-limits timeout output-limit)
  (when (and names-p (zerop (length names)))
    (return-from acquire-configuration (values (make-array 0) (make-array 0) nil)))
  (call-with-operation
   client cancel-token
   (lambda (token)
     (let* ((start (monotonic-seconds))
            (budget (make-capture-budget :start start :deadline (+ start timeout) :remaining output-limit
                                         :row-limit 100000 :field-limit 1048576))
            (reader (make-configuration-reader :client client :token token :budget budget :active-scope scope
                      :decode (make-configuration-decode-budget :remaining-bytes output-limit
                                :remaining-records record-limit :check (lambda () (check-capture-budget budget token))))))
       (handler-case
           (let* ((current (preflight-targets client (and target (list target)) token budget))
                  (target (first current))
                  (witness (slot-value client 'libtmux::witness))
                  (*command-socket-path* (server-witness-endpoint witness))
                  (catalog (configuration-catalog (server-witness-version witness)))
                  (specs nil) (selected-key nil))
             (setf (configuration-reader-witness reader) witness (configuration-reader-catalog reader) catalog)
             (unless names-p
               (setf names (coerce (loop for spec across (option-catalog-options catalog)
                                        when (and (member scope (option-spec-scopes spec))
                                                  (if hooks-only (option-spec-hook-p spec) (not (option-spec-hook-p spec))))
                                          collect (copy-seq (option-spec-name spec))) 'simple-vector)))
             (when (eq domain :option)
               (setf specs (map 'vector (lambda (name)
                                         (setf (configuration-reader-active-name reader) name)
                                         (configuration-reader-check reader)
                                         (catalog-option catalog name scope :hooks-only hooks-only)) names))
               (when key-p
                 (unless (option-spec-array-p (aref specs 0)) (invalid-argument "The requested option is not an array"))
                 (let ((normalized (normalize-option-key catalog key)))
                   (setf selected-key (if (integerp normalized) (write-to-string normalized :base 10 :radix nil) normalized)))))
             (loop for name across names for index from 0
                   do (setf (configuration-reader-active-name reader) name
                            (configuration-reader-active-scope reader) scope
                            (configuration-reader-current-outcome reader) nil)
                      (configuration-reader-check reader)
                      (push (if (eq domain :environment)
                                (configuration-environment-record reader scope target name value-limit)
                                (configuration-option-record reader scope target (aref specs index) inherited hooks-only value-limit))
                            (configuration-reader-records reader)))
             (values (coerce (reverse (configuration-reader-records reader)) 'simple-vector)
                     (coerce (reverse (configuration-reader-outcomes reader)) 'simple-vector) selected-key))
         (error (cause)
           (let ((outcome (or (and (typep cause 'libtmux:libtmux-error) (libtmux:error-outcome cause))
                              (configuration-reader-current-outcome reader))))
             (when (and outcome (not (member outcome (configuration-reader-outcomes reader))))
               (push outcome (configuration-reader-outcomes reader)))
             (error 'libtmux:configuration-read-failed :client client :cause cause :outcome outcome
                    :name (and (configuration-reader-active-name reader) (copy-seq (configuration-reader-active-name reader)))
                    :scope (configuration-reader-active-scope reader)
                    :records (owned-data (coerce (reverse (configuration-reader-records reader)) 'vector))
                    :outcomes (coerce (reverse (configuration-reader-outcomes reader)) 'vector)
                    :message (format nil "Configuration acquisition failed: ~A" cause)))))))))

(in-package #:libtmux)

(define-condition configuration-read-failed (command-failed)
  ((records :initarg :records :initform #()) (outcomes :initarg :outcomes :initform #())
   (name :initarg :name :initform nil) (scope :initarg :scope :initform nil))
  (:documentation "A decoded acquisition failed, retaining prior records and native outcomes.
ERROR-CAUSE identifies the failure. ERROR-OUTCOME retains cause-associated or current
leaf evidence, possibly NIL before the associated read. Its status can be success
when decoding or diagnostics failed. No transport failure becomes absence.
No mutation is retried.
See also: CONFIGURATION-PARTIAL-RECORDS, CONFIGURATION-READ-OUTCOMES,
CONFIGURATION-ERROR-NAME, CONFIGURATION-ERROR-SCOPE, ERROR-CAUSE."))

(defun configuration-error-name (condition)
  "Return the owned active name at failure, or NIL before name resolution. No I/O.
See also: CONFIGURATION-READ-FAILED, CONFIGURATION-ERROR-SCOPE."
  (let ((name (slot-value condition 'name))) (and name (copy-seq name))))

(defun configuration-error-scope (condition)
  "Return the active native table scope at acquisition failure. No I/O.
This may be an ancestor table used for inherited lookup.
See also: CONFIGURATION-ERROR-NAME, CONFIGURATION-READ-FAILED."
  (slot-value condition 'scope))

(defun configuration-partial-records (condition)
  "Return owned copies of records fully resolved before acquisition failed. No I/O.
Inspect CONFIGURATION-READ-OUTCOMES for valid individual observations from a
failing or incomplete name. No partial record proves a complete acquisition.
See also: CONFIGURATION-READ-FAILED, OUTCOME-VALUE."
  (libtmux.internal::owned-data (slot-value condition 'records)))

(defun configuration-read-outcomes (condition)
  "Return a fresh vector of all retained read outcomes, in acquisition order.
Outcome objects retain identity. OUTCOME-VALUE exposes any valid decoded leaf
observation, independently of the native outcome's success status. Preflight
failures can have no selected read outcome. No I/O.
See also: CONFIGURATION-PARTIAL-RECORDS, OUTCOME-VALUE, ERROR-OUTCOME."
  (copy-seq (slot-value condition 'outcomes)))

(defun show-options (client &key scope target (names nil names-p) (include-inherited t)
                                cancel-token timeout output-limit (record-limit 4096) (value-limit 1048576))
  "Acquire decoded options; return owned record and native read-outcome vectors.
SCOPE and TARGET follow SET-OPTION. Omitted NAMES enumerates registered built-in
non-hook names in source order; explicit finite lists/vectors preserve requested
order and duplicates, including user names. At most 4096 names of at most 1 MiB
UTF-8 each are accepted, independently of RECORD-LIMIT. Explicit NIL/#() performs
no I/O after argument validation.
Each plist has :NAME, :SCOPE, :TARGET-ID, :VERSION, :TYPE, :ARRAY-P, :PRESENT-P,
:VALUE, :SOURCE-SCOPE, :SOURCE-TARGET-ID and :INHERITED-P. A present false flag
has NIL value and true presence. Arrays are vectors of (key-text . typed-value)
pairs, including sparse and supported string keys; empty arrays are present.
INCLUDE-INHERITED defaults true: use explicit ancestor tables only after local
absence and recheck every shadowing absence. Observations span an interval,
not a transaction. Read hooks can run again during bounded consistency retries.
One lease, token, deadline and aggregate byte/record budget covers all reads.
RECORD-LIMIT counts decoded rows/negative observations, including rechecks.
VALUE-LIMIT bounds each decoded UTF-8 value. Preparation and cleanup add wall time.
The ordinary printer must match its known schema; unrelated after-read output
signals a decoding failure. This assumes trusted native output, not per-leaf
origin authentication. Raw SHOW-OPTIONS-TEXT preserves unrestricted inspection.
Every requested name has a record even when absent. Read outcomes retain native
failures for expected missing names; this does not prove later hooks succeeded.
Records contain no operational handle; strings/containers own their storage.
See also: SHOW-OPTION, SHOW-HOOKS, SHOW-OPTIONS-TEXT, CONFIGURATION-READ-FAILED."
  (multiple-value-bind (records outcomes)
      (libtmux.internal::acquire-configuration client :option scope target names names-p include-inherited nil
        cancel-token timeout output-limit record-limit value-limit)
    (values records outcomes)))

(defun show-hooks (client &key scope target (names nil names-p) (include-inherited t)
                              cancel-token timeout output-limit (record-limit 4096) (value-limit 1048576))
  "Acquire owned hook records and native read outcomes, following SHOW-OPTIONS.
Omitted NAMES enumerates built-in hooks. Explicit dynamic @ names require a
supporting catalog and remain ordinary strings, without a registration claim.
Builtin command values are inert canonical tmux source. Inspection never requests
set-hook -R; ordinary after-read hooks still apply. :SERVER is unavailable.
No Lisp reader or evaluator parses source.
See also: SHOW-OPTIONS, SHOW-HOOKS-TEXT, SET-HOOK, CONFIGURATION-READ-FAILED."
  (multiple-value-bind (records outcomes)
      (libtmux.internal::acquire-configuration client :option scope target names names-p include-inherited t
        cancel-token timeout output-limit record-limit value-limit)
    (values records outcomes)))

(defun show-option (client name &key scope target (key nil key-p) (include-inherited t)
                               cancel-token timeout output-limit (record-limit 4096) (value-limit 1048576))
  "Acquire one decoded option; return VALUE, PRESENT-P and a read-outcome vector.
False returns NIL,T; absence returns NIL,NIL. KEY selects an entry only after
acquiring a whole named array. A missing key does not fall through a present
local array. Mutable key text is copied before I/O and bounded to 1 MiB UTF-8.
Keys normalize under the exact live catalog before payload reads.
Scopes, limits, inheritance, ownership and failure evidence follow SHOW-OPTIONS.
See also: SHOW-OPTIONS, OUTCOME-VALUE, CONFIGURATION-READ-FAILED."
  (multiple-value-bind (records outcomes normalized)
      (libtmux.internal::acquire-configuration client :option scope target (vector name) t include-inherited nil
        cancel-token timeout output-limit record-limit value-limit :key key :key-p key-p)
    (let ((record (aref records 0)))
      (if key-p
          (let ((entry (and (getf record :present-p)
                            (find normalized (getf record :value) :key #'car :test #'string=))))
            (values (cdr entry) (not (null entry)) outcomes))
          (values (getf record :value) (getf record :present-p) outcomes)))))

(defun show-environment (client &key scope target (names nil names-p)
                                    cancel-token timeout output-limit (record-limit 4096) (value-limit 1048576))
  "Acquire named raw environment entries; return owned record/outcome vectors.
SCOPE is :GLOBAL or :SESSION; session scope requires a captured TARGET. NAMES
is required; explicit NIL/#() performs no I/O. Native names are nonempty UTF-8
without NUL or =, including names outside the mutation identifier grammar.
Each plist has :NAME, :SCOPE, :TARGET-ID, :VERSION, :STATE and :VALUE. States are
:PRESENT, :REMOVED and :ABSENT. Empty strings remain present. Present/removal
records additionally carry explicit :HIDDEN-P; absent records claim no visibility.
Read ordinary visibility first, then hidden only after empty success. Contradictory
views retry under the original limits. This is not a merged child environment.
Shared limits, ordinary-output assumptions and failure evidence follow SHOW-OPTIONS.
See also: SHOW-OPTIONS, SHOW-ENVIRONMENT-TEXT, SET-ENVIRONMENT, CONFIGURATION-READ-FAILED."
  (multiple-value-bind (records outcomes)
      (libtmux.internal::acquire-configuration client :environment scope target names names-p nil nil
        cancel-token timeout output-limit record-limit value-limit)
    (values records outcomes)))
