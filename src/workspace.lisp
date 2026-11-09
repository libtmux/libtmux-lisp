(defpackage #:libtmux.workspace
  (:use #:cl)
  (:documentation "Owned Common Lisp workspace descriptions and explicit tmux application.
MAKE-WORKSPACE validates inert native data without evaluation. PLAN-WORKSPACE
is local and pure; APPLY-WORKSPACE is the explicit external-operation boundary.
Workspace objects, plans, steps, results, and their readers return defensive
data. Conflicts fail before mutation, and partial application retains evidence.")
  (:export
   #:workspace #:workspace-plan #:workspace-step #:workspace-result
   #:workspace-error #:invalid-workspace #:workspace-conflict
   #:invalid-workspace-document #:workspace-limit-exceeded
   #:workspace-apply-failed #:workspace-deadline-exceeded
   #:workspace-path #:workspace-limit #:failed-step
   #:make-workspace #:workspace-data #:parse-workspace #:read-workspace
   #:plan-workspace #:plan-steps #:step-action #:step-data
   #:apply-workspace #:result-snapshot #:result-outcomes #:result-created-p))

(in-package #:libtmux.workspace)

(defparameter +schema+ "libtmux.lisp.workspace/1")
(defparameter +layouts+
  '(:even-horizontal :even-vertical :main-horizontal :main-vertical :tiled))

(defgeneric workspace-path (condition)
  (:documentation "Return a fresh vector locating the workspace error, without I/O."))

(defgeneric workspace-limit (condition)
  (:documentation "Return the exhausted workspace limit name, or NIL, without I/O."))

(defgeneric failed-step (condition)
  (:documentation "Return the failed or refused next WORKSPACE-STEP, or NIL for final verification.
NIL does not imply that no mutations completed; inspect RESULT-OUTCOMES.

See also: RESULT-OUTCOMES, APPLY-WORKSPACE."))

(defgeneric workspace-data (workspace)
  (:documentation "Return fresh closed native data for WORKSPACE, without I/O.

See also: MAKE-WORKSPACE, PLAN-WORKSPACE."))

(defgeneric step-action (step)
  (:documentation "Return STEP's action keyword, without I/O.

See also: STEP-DATA, PLAN-STEPS."))

(defgeneric step-data (step)
  (:documentation "Return a fresh plist of STEP operands, without I/O.

See also: STEP-ACTION, PLAN-STEPS."))

(defgeneric plan-steps (plan)
  (:documentation "Return PLAN's ordered steps as a fresh simple vector. No I/O.

See also: PLAN-WORKSPACE, STEP-ACTION, STEP-DATA."))

(defgeneric result-snapshot (result)
  (:documentation "Return the final captured SNAPSHOT retained by RESULT. No I/O.

See also: RESULT-OUTCOMES, RESULT-CREATED-P, APPLY-WORKSPACE."))

(defgeneric result-outcomes (result)
  (:documentation "Return retained COMMAND-OUTCOME objects in a fresh simple vector.

See also: RESULT-SNAPSHOT, RESULT-CREATED-P, FAILED-STEP."))

(defgeneric result-created-p (result)
  (:documentation "Return true when APPLY-WORKSPACE created the declared session.

See also: RESULT-SNAPSHOT, RESULT-OUTCOMES, APPLY-WORKSPACE."))

(define-condition workspace-error (libtmux:libtmux-error)
  ((path :initarg :path :initform #())
   (limit :initarg :limit :initform nil))
  (:documentation "A workspace validation, planning, or application failure."))

(define-condition invalid-workspace (workspace-error) ()
  (:documentation "Native workspace data violates the closed workspace grammar."))

(define-condition workspace-conflict (workspace-error) ()
  (:documentation "Captured topology conflicts with the declared workspace."))

(define-condition invalid-workspace-document (invalid-workspace) ()
  (:documentation "A workspace JSON document is malformed, unknown, or invalid."))

(define-condition workspace-limit-exceeded (invalid-workspace-document) ()
  (:documentation "A workspace JSON or file input exceeds a configured bound."))

(define-condition workspace-apply-failed (workspace-error)
  ((step :initarg :step :initform nil)
   (outcomes :initarg :outcomes :initform #()))
  (:documentation "Workspace application stopped with retained partial outcomes."))

(define-condition workspace-deadline-exceeded (workspace-error) ()
  (:documentation "The application budget expired at a workspace boundary.
WORKSPACE-LIMIT returns :TOTAL-TIMEOUT. No new command outcome is implied;
previous completed outcomes remain on a wrapping WORKSPACE-APPLY-FAILED.
An already admitted core call retains its own timeout and cleanup contract.

See also: APPLY-WORKSPACE, WORKSPACE-LIMIT, RESULT-OUTCOMES."))

(defmethod workspace-path ((condition workspace-error))
  (deep-copy (slot-value condition 'path)))

(defmethod workspace-limit ((condition workspace-error))
  (slot-value condition 'limit))

(defmethod failed-step ((condition workspace-apply-failed))
  (slot-value condition 'step))

(defstruct (pane-spec (:constructor %make-pane-spec
                        (&key cwd cwd-p command command-p shell-command shell-command-p)))
  cwd cwd-p command command-p shell-command shell-command-p)

(defstruct (window-spec
            (:constructor %make-window-spec
                (&key name index index-p cwd cwd-p layout layout-p panes)))
  name index index-p cwd cwd-p layout layout-p panes)

(defstruct (session-spec (:constructor %make-session-spec
                           (&key name cwd cwd-p environment environment-p windows)))
  name cwd cwd-p environment environment-p windows)

(defclass workspace ()
  ((session :initarg :session)
   (data :initarg :data))
  (:documentation "An immutable-by-contract, owned workspace description."))

(defclass workspace-step ()
  ((action :initarg :action :reader step-action)
   (data :initarg :data))
  (:documentation "One inspectable, inert workspace operation in execution order."))

(defclass workspace-plan ()
  ((steps :initarg :steps))
  (:documentation "A finite local plan; an empty step vector is a proven no-op."))

(defclass workspace-result ()
  ((snapshot :initarg :snapshot :reader result-snapshot)
   (outcomes :initarg :outcomes)
   (created-p :initarg :created-p :reader result-created-p))
  (:documentation "Retained workspace application evidence and final captured topology."))

(defun deep-copy (value)
  (typecase value
    (string (copy-seq value))
    (cons (cons (deep-copy (car value)) (deep-copy (cdr value))))
    (vector (map 'simple-vector #'deep-copy value))
    (t value)))

(defun path+ (path &rest components)
  (concatenate 'simple-vector path (coerce components 'simple-vector)))

(defmethod step-data ((step workspace-step))
  "Return a fresh plist describing STEP's logical target and operands. No I/O.
Mutating the returned strings or containers cannot alter the plan.

See also: STEP-ACTION, PLAN-STEPS."
  (deep-copy (slot-value step 'data)))

(defmethod plan-steps ((plan workspace-plan))
  "Return PLAN's steps as a fresh simple vector in execution order. No I/O.
Step objects are immutable-by-contract and may be shared; each STEP-DATA call
returns owned data. An empty vector represents a proven no-op.

See also: PLAN-WORKSPACE, STEP-ACTION, STEP-DATA."
  (copy-seq (slot-value plan 'steps)))

(defmethod result-outcomes ((result workspace-result))
  "Return completed core COMMAND-OUTCOME objects in a fresh simple vector.
The outcomes retain dispatch evidence; their own mutable readers return copies.

See also: RESULT-SNAPSHOT, RESULT-CREATED-P, APPLY-WORKSPACE."
  (copy-seq (slot-value result 'outcomes)))

(defmethod result-outcomes ((condition workspace-apply-failed))
  (copy-seq (slot-value condition 'outcomes)))

(defun fail-workspace (message &key path limit (type 'invalid-workspace) cause)
  (error type :message message :path (coerce path 'simple-vector)
              :limit limit :cause cause))

(defun checked-limit (value name &optional (minimum 0))
  (unless (and (integerp value) (>= value minimum))
    (fail-workspace (format nil "~S must be an integer no smaller than ~D" name minimum)))
  value)

(defun finite-list-length (value path description)
  (unless (listp value)
    (fail-workspace (format nil "~A must be a finite proper plist" description)
                    :path path))
  (let ((length (handler-case (list-length value) (type-error () nil))))
    (unless (or length (null value))
      (fail-workspace (format nil "~A must be a finite proper plist" description)
                      :path path))
    (or length 0)))

(defun closed-plist (value allowed path description)
  (let ((length (finite-list-length value path description))
        (seen nil))
    (unless (evenp length)
      (fail-workspace (format nil "~A must contain key/value pairs" description)
                      :path path))
    (loop for cursor on value by #'cddr
          for key = (first cursor)
          do (unless (member key allowed :test #'eq)
               (fail-workspace (format nil "Unknown key in ~A" description)
                               :path (path+ path :unknown-key)))
             (when (member key seen :test #'eq)
               (fail-workspace (format nil "~S occurs more than once in ~A" key description)
                               :path (path+ path key)))
             (push key seen)))
  value)

(defun plist-value (plist key)
  (loop for (candidate value) on plist by #'cddr
        when (eq candidate key) return (values value t)
        finally (return (values nil nil))))

(defun finite-sequence (value path description)
  (cond
    ((and (vectorp value) (not (stringp value)))
     (map 'simple-vector #'identity value))
    ((listp value)
     (let ((length (handler-case (list-length value) (type-error () nil))))
       (unless (or length (null value))
         (fail-workspace (format nil "~A must be a finite proper list or vector" description)
                         :path path))
       (coerce value 'simple-vector)))
    (t
     (fail-workspace (format nil "~A must be a finite list or vector" description)
                     :path path))))

(defun owned-text (value path description &key (empty-p nil))
  (unless (and (stringp value) (not (find #\Null value))
               (or empty-p (plusp (length value))))
    (fail-workspace (format nil "~A must be a ~Astring without NUL"
                            description (if empty-p "" "nonempty "))
                    :path path))
  (copy-seq value))

(defun owned-tmux-name (value path description &key session-p)
  (let ((name (owned-text value path description)))
    (when (or (and session-p (find-if (lambda (character)
                                       (find character ".:"))
                                     name))
              (find-if (lambda (character)
                         (let ((code (char-code character)))
                           (or (< code 32) (= code 127) (char= character #\\))))
                       name))
      (fail-workspace
       (format nil "~A contains characters tmux cannot preserve" description)
       :path path))
    name))

(defun normalized-command (value path max-argv)
  (let ((arguments (finite-sequence value path "Command")))
    (when (or (zerop (length arguments)) (> (length arguments) max-argv))
      (fail-workspace (format nil "Command must contain 1 through ~D argv strings" max-argv)
                      :path path))
    (map-into arguments
              (lambda (argument)
                (owned-text argument path "Command argument" :empty-p t))
              arguments)
    (when (or (zerop (length (aref arguments 0)))
              (char= #\- (char (aref arguments 0) 0)))
      (fail-workspace "Command argv needs a nonempty executable that does not begin with '-'"
                      :path path))
    arguments))

(defun normalized-environment (value path maximum)
  (let ((entries (finite-sequence value path "Session environment"))
        (names (make-hash-table :test #'equal)))
    (when (> (length entries) maximum)
      (fail-workspace "Session environment exceeds MAX-ENVIRONMENT"
                      :path path :limit :max-environment))
    (loop for entry across entries for index from 0
          for entry-path = (path+ path index)
          do (unless (consp entry)
               (fail-workspace "Environment entries must be (name . value) string pairs"
                               :path entry-path))
          collect (let ((name (owned-text (car entry) entry-path "Environment name"))
                        (value (owned-text (cdr entry) entry-path "Environment value"
                                           :empty-p t)))
                    (when (or (find #\= name) (gethash name names))
                      (fail-workspace "Environment names must be unique and cannot contain '='"
                                      :path entry-path))
                    (setf (gethash name names) t)
                    (cons name value)) into result
          finally (return (coerce result 'simple-vector)))))

(defun normalized-layout (layout path)
  (cond ((member layout +layouts+ :test #'eq) layout)
        ((and (listp layout) (= 2 (finite-list-length layout path "Custom layout"))
              (eq (first layout) :custom))
         (list :custom (owned-text (second layout) path "Custom layout")))
        (t (fail-workspace "Layout must be a named keyword or (:CUSTOM string)"
                           :path path))))

(defun normalize-pane (data path max-argv)
  (closed-plist data '(:cwd :command :shell-command) path "Pane")
  (multiple-value-bind (cwd cwd-p) (plist-value data :cwd)
    (multiple-value-bind (command command-p) (plist-value data :command)
      (multiple-value-bind (shell shell-p) (plist-value data :shell-command)
        (when (and command-p shell-p)
          (fail-workspace "Specify :COMMAND argv or :SHELL-COMMAND source, not both"
                          :path path))
        (%make-pane-spec
         :cwd (when cwd-p (owned-text cwd (path+ path :cwd) "Pane CWD"))
         :cwd-p cwd-p
         :command (when command-p
                    (normalized-command command (path+ path :command) max-argv))
         :command-p command-p
         :shell-command (when shell-p
                          (owned-text shell (path+ path :shell-command) "Shell source"))
         :shell-command-p shell-p)))))

(defun normalize-window (data path max-panes max-argv)
  (closed-plist data '(:name :index :cwd :layout :panes) path "Window")
  (multiple-value-bind (name name-p) (plist-value data :name)
    (unless name-p (fail-workspace "Window :NAME is required" :path (path+ path :name)))
    (multiple-value-bind (panes panes-p) (plist-value data :panes)
      (unless panes-p (fail-workspace "Window :PANES is required" :path (path+ path :panes)))
      (let ((panes (finite-sequence panes (path+ path :panes) "Window panes")))
        (unless (and (plusp (length panes)) (<= (length panes) max-panes))
          (fail-workspace (format nil "Window must contain 1 through ~D panes" max-panes)
                          :path (path+ path :panes)))
        (multiple-value-bind (index index-p) (plist-value data :index)
          (when (and index-p
                     (not (and (integerp index) (<= 0 index 2147483647))))
            (fail-workspace "Window index must be an integer from 0 through 2147483647"
                            :path (path+ path :index)))
          (multiple-value-bind (cwd cwd-p) (plist-value data :cwd)
            (multiple-value-bind (layout layout-p) (plist-value data :layout)
              (%make-window-spec
               :name (owned-tmux-name name (path+ path :name) "Window name")
               :index index :index-p index-p
               :cwd (when cwd-p (owned-text cwd (path+ path :cwd) "Window CWD"))
               :cwd-p cwd-p
               :layout (when layout-p (normalized-layout layout (path+ path :layout)))
               :layout-p layout-p
               :panes
               (loop with result = (make-array (length panes))
                     for pane across panes
                     for pane-index from 0
                     do (setf (aref result pane-index)
                              (normalize-pane pane (path+ path :panes pane-index)
                                              max-argv))
                     finally (return result))))))))))

(defun pane-data (pane)
  (append (when (pane-spec-cwd-p pane) (list :cwd (copy-seq (pane-spec-cwd pane))))
          (when (pane-spec-command-p pane)
            (list :command (deep-copy (pane-spec-command pane))))
          (when (pane-spec-shell-command-p pane)
            (list :shell-command (copy-seq (pane-spec-shell-command pane))))))

(defun window-data (window)
  (append (list :name (copy-seq (window-spec-name window)))
          (when (window-spec-index-p window) (list :index (window-spec-index window)))
          (when (window-spec-cwd-p window) (list :cwd (copy-seq (window-spec-cwd window))))
          (when (window-spec-layout-p window)
            (list :layout (deep-copy (window-spec-layout window))))
          (list :panes (map 'simple-vector #'pane-data (window-spec-panes window)))))

(defun normalized-data (session)
  (list :schema (copy-seq +schema+)
        :session
        (append (list :name (copy-seq (session-spec-name session)))
                (when (session-spec-cwd-p session)
                  (list :cwd (copy-seq (session-spec-cwd session))))
                (when (session-spec-environment-p session)
                  (list :environment (deep-copy (session-spec-environment session))))
                (list :windows (map 'simple-vector #'window-data
                                    (session-spec-windows session))))))

(defun make-workspace (data &key (max-windows 100) (max-panes 1000) (max-argv 256)
                                (max-environment 256))
  "Validate closed native DATA and return an owned WORKSPACE without I/O.
DATA is a keyword plist in schema libtmux.lisp.workspace/1. Lists and vectors
must be finite. MAX-WINDOWS, MAX-PANES, and MAX-ARGV bound retained topology and
commands. MAX-ENVIRONMENT bounds session (name . value) string pairs; tmux
stores them in the session environment inherited by later panes. Pane :COMMAND
is argv; :SHELL-COMMAND is explicit shell source, mutually exclusive with argv.
Window :LAYOUT is a named keyword or (:CUSTOM string) validated by tmux on apply.
Names reject characters tmux would rewrite. Unknown/duplicate keys, invalid
types or limits signal INVALID-WORKSPACE. Mutable inputs are copied.

See also: WORKSPACE-DATA, PLAN-WORKSPACE, PARSE-WORKSPACE,
LIBTMUX:NEW-SESSION, LIBTMUX:SELECT-LAYOUT."
  (checked-limit max-windows :max-windows 1)
  (checked-limit max-panes :max-panes 1)
  (checked-limit max-argv :max-argv 0)
  (checked-limit max-environment :max-environment 0)
  (closed-plist data '(:schema :session) #() "Workspace")
  (multiple-value-bind (schema schema-p) (plist-value data :schema)
    (unless (and schema-p (stringp schema) (string= schema +schema+))
      (fail-workspace "Unsupported or missing workspace :SCHEMA" :path #(:schema)))
    (multiple-value-bind (session-data session-p) (plist-value data :session)
      (unless session-p
        (fail-workspace "Workspace :SESSION is required" :path #(:session)))
      (closed-plist session-data '(:name :cwd :environment :windows) #(:session) "Session")
      (multiple-value-bind (name name-p) (plist-value session-data :name)
        (unless name-p
          (fail-workspace "Session :NAME is required" :path #(:session :name)))
        (multiple-value-bind (windows windows-p) (plist-value session-data :windows)
          (unless windows-p
            (fail-workspace "Session :WINDOWS is required" :path #(:session :windows)))
          (let ((windows (finite-sequence windows #(:session :windows) "Session windows")))
            (unless (and (plusp (length windows)) (<= (length windows) max-windows))
              (fail-workspace (format nil "Session must contain 1 through ~D windows" max-windows)
                              :path #(:session :windows)))
            (multiple-value-bind (cwd cwd-p) (plist-value session-data :cwd)
              (let* ((specs
                       (loop for window across windows for index from 0
                             collect (normalize-window
                                      window (vector :session :windows index)
                                      max-panes max-argv)))
                     (total-panes (reduce #'+ specs :key (lambda (window)
                                                          (length (window-spec-panes window)))))
                     (names (mapcar #'window-spec-name specs))
                     (indexes (loop for window in specs when (window-spec-index-p window)
                                    collect (window-spec-index window))))
                (when (> total-panes max-panes)
                  (fail-workspace (format nil "Workspace contains more than ~D panes" max-panes)
                                  :path #(:session :windows)))
                (unless (= (length names) (length (remove-duplicates names :test #'string=)))
                  (fail-workspace "Window names must be unique" :path #(:session :windows)))
                (unless (= (length indexes) (length (remove-duplicates indexes :test #'=)))
                  (fail-workspace "Explicit window indexes must be unique"
                                  :path #(:session :windows)))
                (let* ((session
                         (%make-session-spec
                          :name (owned-tmux-name name #(:session :name) "Session name"
                                                 :session-p t)
                          :cwd (when cwd-p (owned-text cwd #(:session :cwd) "Session CWD"))
                          :cwd-p cwd-p
                          :environment
                          (when (nth-value 1 (plist-value session-data :environment))
                            (normalized-environment (getf session-data :environment)
                                                    #(:session :environment) max-environment))
                          :environment-p (nth-value 1 (plist-value session-data :environment))
                          :windows (coerce specs 'simple-vector)))
                       (normalized (normalized-data session)))
                  (make-instance 'workspace :session session :data normalized))))))))))

(defmethod workspace-data ((workspace workspace))
  "Return a fresh closed native plist for WORKSPACE, without I/O.
The result uses vectors for windows, panes, and argv. Mutating it cannot alter
the retained workspace.

See also: MAKE-WORKSPACE, PLAN-WORKSPACE."
  (deep-copy (slot-value workspace 'data)))

(defun effective-cwd (pane window session)
  (cond ((pane-spec-cwd-p pane) (pane-spec-cwd pane))
        ((window-spec-cwd-p window) (window-spec-cwd window))
        ((session-spec-cwd-p session) (session-spec-cwd session))))

(defun make-step (action &rest data)
  (make-instance 'workspace-step :action action :data (deep-copy data)))

(defun pane-step-data (session window pane position)
  (let ((cwd (effective-cwd pane window session)))
    (append (list :window-name (copy-seq (window-spec-name window))
                  :pane-position position)
            (when cwd (list :cwd (copy-seq cwd)))
            (when (pane-spec-command-p pane)
              (list :command (deep-copy (pane-spec-command pane))))
            (when (pane-spec-shell-command-p pane)
              (list :shell-command (copy-seq (pane-spec-shell-command pane)))))))

(defun first-pane-data (session window)
  (let* ((pane (aref (window-spec-panes window) 0))
         (cwd (effective-cwd pane window session)))
    (append (when cwd (list :cwd (copy-seq cwd)))
            (when (pane-spec-command-p pane)
              (list :command (deep-copy (pane-spec-command pane))))
            (when (pane-spec-shell-command-p pane)
              (list :shell-command (copy-seq (pane-spec-shell-command pane)))))))

(defun append-pane-steps (steps session window)
  (let* ((panes (window-spec-panes window))
         (last-position (1- (length panes)))
         (layout (and (window-spec-layout-p window) (window-spec-layout window))))
    (loop for position from 1 to last-position
          for pane = (aref panes position)
          do (setf steps
                   (append steps
                           (list (apply #'make-step :split-pane
                                        :direction :adaptive :target :last
                                        (pane-step-data session window pane position)))))
             (when (< position last-position)
               (setf steps
                     (append steps
                             (list (make-step :select-layout
                                              :window-name (window-spec-name window)
                                              :layout :tiled))))))
    (when layout
      (setf steps
            (append steps (list (make-step :select-layout
                                           :window-name (window-spec-name window)
                                           :layout layout)))))
    steps))

(defun first-free-index (reserved)
  (loop for index from 0
        unless (member index reserved :test #'=) return index))

(defun creation-steps (workspace)
  (let* ((session (slot-value workspace 'session))
         (windows (session-spec-windows session))
         (first (aref windows 0))
         (remaining (loop for position from 1 below (length windows)
                          collect (aref windows position)))
         (explicit (remove-if-not #'window-spec-index-p remaining))
         (automatic (remove-if #'window-spec-index-p remaining))
         (reserved (mapcar #'window-spec-index explicit))
         (steps
           (list (apply #'make-step :create-session
                        :session-name (session-spec-name session)
                        :window-name (window-spec-name first)
                        (append (first-pane-data session first)
                                (when (session-spec-environment-p session)
                                  (list :environment
                                        (deep-copy (session-spec-environment session)))))))))
    (when (or (window-spec-index-p first) reserved)
      (setf steps
            (append steps
                    (list (make-step :move-window
                                     :window-name (window-spec-name first)
                                     :index (if (window-spec-index-p first)
                                                (window-spec-index first)
                                                (first-free-index reserved)))))))
    (setf steps (append-pane-steps steps session first))
    (dolist (window (append explicit automatic))
      (setf steps
            (append steps
                    (list
                     (apply #'make-step :create-window
                            :window-name (window-spec-name window)
                            (append
                             (when (window-spec-index-p window)
                               (list :index (window-spec-index window)))
                             (first-pane-data session window))))))
      (setf steps (append-pane-steps steps session window)))
    (coerce steps 'simple-vector)))

(defun conflict (message &optional path)
  (fail-workspace message :type 'workspace-conflict :path (or path #())))

(defun matching-session (snapshot name)
  (let ((matches (remove-if-not (lambda (session) (string= name (libtmux:name session)))
                                (libtmux:sessions snapshot))))
    (cond ((zerop (length matches)) nil)
          ((= 1 (length matches)) (aref matches 0))
          (t (conflict "Captured workspace session name is ambiguous" #(:session :name))))))

(defun prove-topology (workspace session)
  (let* ((declared (session-spec-windows (slot-value workspace 'session)))
         (links (libtmux:window-links session)))
    (unless (= (length declared) (length links))
      (conflict "Captured workspace has a different number of window links"
                #(:session :windows)))
    (loop for wanted across declared for position from 0
          for matches = (remove-if-not
                         (lambda (link)
                           (string= (window-spec-name wanted)
                                    (libtmux:name (libtmux:window link))))
                         links)
          do (unless (= 1 (length matches))
               (conflict "A declared window name is missing or ambiguous"
                         (vector :session :windows position :name)))
             (let* ((link (aref matches 0))
                    (window (libtmux:window link)))
               (when (and (window-spec-index-p wanted)
                          (/= (window-spec-index wanted) (libtmux:index link)))
                 (conflict "A declared window index differs from the captured link"
                           (vector :session :windows position :index)))
               (unless (= (length (window-spec-panes wanted))
                          (length (libtmux:panes window)))
                 (conflict "A declared window has a different captured pane count"
                           (vector :session :windows position :panes)))))))

(defun plan-workspace (workspace &optional snapshot)
  "Return a finite local WORKSPACE-PLAN, optionally against captured SNAPSHOT.
Without SNAPSHOT, return the deterministic creation plan. With SNAPSHOT, return
that plan when the named session is absent, an empty proven no-op when topology
matches, or signal WORKSPACE-CONFLICT before dispatch. Planning compares window
names, declared indexes, and pane counts; creation-only cwd, argv, and layout
are not inferred from mutable live state. Explicit indexes are reserved before
automatic windows. Pane creation and final order follow the declaration. No
tmux I/O occurs.

See also: PLAN-STEPS, WORKSPACE-DATA, APPLY-WORKSPACE."
  (check-type workspace workspace)
  (when snapshot (check-type snapshot libtmux:snapshot))
  (let* ((session-spec (slot-value workspace 'session))
         (session (and snapshot (matching-session snapshot (session-spec-name session-spec)))))
    (make-instance 'workspace-plan
                   :steps (if session
                              (progn (prove-topology workspace session) #())
                              (creation-steps workspace)))))

(defconstant +default-max-input-bytes+ 1048576)
(defconstant +default-max-depth+ 32)
(defconstant +default-max-nodes+ 10000)
(defconstant +default-max-string-length+ 65536)
(defconstant +default-max-windows+ 100)
(defconstant +default-max-panes+ 1000)
(defconstant +default-max-argv+ 256)
(defconstant +default-max-environment+ 256)
(defconstant +default-max-integer-digits+ 32)

(defstruct (json-object (:constructor make-json-object (entries)))
  entries)

(defun fail-document (message &key (path #()) limit cause)
  (error (if limit 'workspace-limit-exceeded 'invalid-workspace-document)
         :message message :path (deep-copy (coerce path 'simple-vector))
         :limit limit :cause cause))

(defun document-path+ (path component)
  (concatenate 'simple-vector path (vector (deep-copy component))))

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
                (format nil "Workspace document exceeds ~D UTF-8 bytes" limit)
                :limit :max-input-bytes)))
    size))

(defun json-number-delimiter-p (character)
  (member character
          '(#\Space #\Tab #\Return #\Linefeed #\, #\] #\} #\{ #\[ #\:)
          :test #'char=))

(defun validate-json-integers (source limit)
  (let ((index 0) (length (length source)) (in-string nil) (escaped nil))
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
                                   (not (json-number-delimiter-p (char source cursor))))
                        do (incf cursor))
                  (let* ((first-digit (if (char= character #\-) (1+ index) index))
                         (digits (- cursor first-digit)))
                    (unless (loop for position from first-digit below cursor
                                  always (digit-char-p (char source position)))
                      (fail-document "Workspace documents accept integer JSON numbers only"
                                     :path #()))
                    (when (> digits limit)
                      (fail-document
                       (format nil "A numeric token exceeds ~D decimal digits" limit)
                       :limit :max-integer-digits))
                    (setf index cursor))))
               (t (incf index))))))

(defun parse-json-events (source max-depth max-nodes max-string-length)
  (let ((nodes 0))
    (labels ((checkpoint (path)
               (when (> (incf nodes) max-nodes)
                 (fail-document
                  (format nil "Workspace document exceeds ~D JSON nodes" max-nodes)
                  :path path :limit :max-nodes)))
             (read-event (parser event value depth path)
               (checkpoint path)
               (case event
                 (:value value)
                 (:begin-array
                  (when (> depth max-depth)
                    (fail-document
                     (format nil "Workspace document exceeds nesting depth ~D" max-depth)
                     :path path :limit :max-depth))
                  (let ((items (make-array 4 :adjustable t :fill-pointer 0))
                        (index 0))
                    (loop
                      (multiple-value-bind (next-event next-value)
                          (com.inuoe.jzon:parse-next parser)
                        (cond
                          ((eq next-event :end-array) (return))
                          ((null next-event)
                           (fail-document "Unexpected end of JSON array" :path path))
                          (t
                           (vector-push-extend
                            (read-event parser next-event next-value (1+ depth)
                                        (document-path+ path index))
                            items)
                           (incf index)))))
                    (coerce items 'simple-vector)))
                 (:begin-object
                  (when (> depth max-depth)
                    (fail-document
                     (format nil "Workspace document exceeds nesting depth ~D" max-depth)
                     :path path :limit :max-depth))
                  (let ((entries nil) (seen (make-hash-table :test 'equal)))
                    (loop
                      (multiple-value-bind (next-event key)
                          (com.inuoe.jzon:parse-next parser)
                        (cond
                          ((eq next-event :end-object) (return))
                          ((null next-event)
                           (fail-document "Unexpected end of JSON object" :path path))
                          ((not (eq next-event :object-key))
                           (fail-document "Expected a JSON object member" :path path))
                          ((gethash key seen)
                           (fail-document "A JSON object member occurs more than once"
                                          :path (document-path+ path key)))
                          (t
                           (setf (gethash key seen) t)
                           (multiple-value-bind (value-event member-value)
                               (com.inuoe.jzon:parse-next parser)
                             (when (null value-event)
                               (fail-document "A JSON object member has no value"
                                              :path (document-path+ path key)))
                             (push (cons (copy-seq key)
                                         (read-event parser value-event member-value
                                                     (1+ depth)
                                                     (document-path+ path key)))
                                   entries))))))
                    (make-json-object (nreverse entries))))
                 ((:end-array :end-object :object-key)
                  (fail-document "Unexpected JSON structural token" :path path))
                 (otherwise
                  (fail-document "Unexpected end of JSON input" :path path))))
             (parse-root ()
               (com.inuoe.jzon:with-parser
                   (parser source :max-string-length max-string-length :key-fn nil)
                 (multiple-value-bind (event value) (com.inuoe.jzon:parse-next parser)
                   (unless event
                     (fail-document "A workspace document must contain one JSON value"))
                   (let ((result (read-event parser event value 1 #())))
                     (multiple-value-bind (extra-event extra-value)
                         (com.inuoe.jzon:parse-next parser)
                       (declare (ignore extra-value))
                       (when extra-event
                         (fail-document "A workspace document must contain one JSON value")))
                     result)))))
      (handler-case (parse-root)
        (workspace-error (condition) (error condition))
        (com.inuoe.jzon:json-parse-limit-error (cause)
          (fail-document "Jzon exhausted the configured string bound"
                         :limit :max-string-length :cause cause))
        (com.inuoe.jzon:json-error (cause)
          (fail-document "Jzon rejected the workspace document" :cause cause))))))

(defun object-member (object name)
  (let ((entry (and (json-object-p object)
                    (assoc name (json-object-entries object) :test #'string=))))
    (if entry (values (cdr entry) t) (values nil nil))))

(defun required-member (object name path)
  (multiple-value-bind (value present-p) (object-member object name)
    (unless present-p
      (fail-document "A required workspace-document member is missing"
                     :path (document-path+ path name)))
    value))

(defun closed-object (object allowed path description)
  (unless (json-object-p object)
    (fail-document (format nil "~A must be a JSON object" description) :path path))
  (dolist (entry (json-object-entries object))
    (unless (member (car entry) allowed :test #'string=)
      (fail-document (format nil "A member is not allowed in ~A" description)
                     :path (document-path+ path (car entry)))))
  object)

(defun json-string (value path description)
  (unless (stringp value)
    (fail-document (format nil "~A must be a JSON string" description) :path path))
  (copy-seq value))

(defun json-array (value path description)
  (unless (and (vectorp value) (not (stringp value)))
    (fail-document (format nil "~A must be a JSON array" description) :path path))
  value)

(defun optional-json-member (object name path function)
  (multiple-value-bind (value present-p) (object-member object name)
    (when present-p
      (values (funcall function value (document-path+ path name)) t))))

(defun wire-command (value path max-argv)
  (let ((arguments (json-array value path "Command")))
    (when (> (length arguments) max-argv)
      (fail-document (format nil "Command contains more than ~D argv strings" max-argv)
                     :path path :limit :max-argv))
    (map 'simple-vector
         (lambda (argument) (json-string argument path "Command argument"))
         arguments)))

(defun wire-pane (object path max-argv)
  (closed-object object '("cwd" "command" "shell_command") path "Pane")
  (let ((result nil))
    (multiple-value-bind (cwd present-p)
        (optional-json-member object "cwd" path
                              (lambda (value member-path)
                                (json-string value member-path "Pane cwd")))
      (when present-p (setf result (append result (list :cwd cwd)))))
    (multiple-value-bind (command present-p)
        (optional-json-member object "command" path
                              (lambda (value member-path)
                                (wire-command value member-path max-argv)))
      (when present-p (setf result (append result (list :command command)))))
    (multiple-value-bind (shell present-p)
        (optional-json-member object "shell_command" path
                              (lambda (value member-path)
                                (json-string value member-path "Shell source")))
      (when present-p (setf result (append result (list :shell-command shell)))))
    result))

(defun wire-layout (value path)
  (when (json-object-p value)
    (closed-object value '("custom") path "Custom layout")
    (return-from wire-layout
      (list :custom (json-string (required-member value "custom" path)
                                (document-path+ path "custom") "Custom layout"))))
  (let* ((name (json-string value path "Window layout"))
         (entry (assoc name '(("even-horizontal" . :even-horizontal)
                              ("even-vertical" . :even-vertical)
                              ("main-horizontal" . :main-horizontal)
                              ("main-vertical" . :main-vertical)
                              ("tiled" . :tiled))
                       :test #'string=)))
    (unless entry
      (fail-document "Unknown named window layout" :path path))
    (cdr entry)))

(defun wire-window (object path max-panes max-argv)
  (closed-object object '("name" "index" "cwd" "layout" "panes") path "Window")
  (let* ((name (json-string (required-member object "name" path)
                            (document-path+ path "name") "Window name"))
         (panes-source (json-array (required-member object "panes" path)
                                   (document-path+ path "panes") "Window panes")))
    (when (> (length panes-source) max-panes)
      (fail-document (format nil "Window contains more than ~D panes" max-panes)
                     :path (document-path+ path "panes") :limit :max-panes))
    (let ((result (list :name name)))
      (multiple-value-bind (index present-p) (object-member object "index")
        (when present-p
          (unless (integerp index)
            (fail-document "Window index must be a JSON integer"
                           :path (document-path+ path "index")))
          (setf result (append result (list :index index)))))
      (multiple-value-bind (cwd present-p)
          (optional-json-member object "cwd" path
                                (lambda (value member-path)
                                  (json-string value member-path "Window cwd")))
        (when present-p (setf result (append result (list :cwd cwd)))))
      (multiple-value-bind (layout present-p)
          (optional-json-member object "layout" path #'wire-layout)
        (when present-p (setf result (append result (list :layout layout)))))
      (append result
              (list :panes
                    (loop with panes = (make-array (length panes-source))
                          for pane across panes-source for index from 0
                          do (setf (aref panes index)
                                   (wire-pane pane
                                              (document-path+
                                               (document-path+ path "panes") index)
                                              max-argv))
                          finally (return panes)))))))

(defun wire-environment (object path maximum)
  (unless (json-object-p object)
    (fail-document "Session environment must be a JSON object" :path path))
  (when (> (length (json-object-entries object)) maximum)
    (fail-document "Session environment exceeds MAX-ENVIRONMENT"
                   :path path :limit :max-environment))
  (map 'simple-vector
       (lambda (entry)
         (cons (copy-seq (car entry))
               (json-string (cdr entry) (document-path+ path (car entry))
                            "Environment value")))
       (json-object-entries object)))

(defun wire-session (object path max-windows max-panes max-argv max-environment)
  (closed-object object '("name" "cwd" "environment" "windows") path "Session")
  (let* ((name (json-string (required-member object "name" path)
                            (document-path+ path "name") "Session name"))
         (windows-source (json-array (required-member object "windows" path)
                                     (document-path+ path "windows") "Session windows")))
    (when (> (length windows-source) max-windows)
      (fail-document (format nil "Session contains more than ~D windows" max-windows)
                     :path (document-path+ path "windows") :limit :max-windows))
    (let ((result (list :name name))
          (total-panes 0))
      (multiple-value-bind (cwd present-p)
          (optional-json-member object "cwd" path
                                (lambda (value member-path)
                                  (json-string value member-path "Session cwd")))
        (when present-p (setf result (append result (list :cwd cwd)))))
      (multiple-value-bind (environment present-p)
          (optional-json-member object "environment" path
                                (lambda (value member-path)
                                  (wire-environment value member-path max-environment)))
        (when present-p (setf result (append result (list :environment environment)))))
      (append
       result
       (list
        :windows
        (loop with windows = (make-array (length windows-source))
              for window across windows-source for index from 0
              for native = (wire-window
                            window (document-path+ (document-path+ path "windows") index)
                            max-panes max-argv)
              do (incf total-panes (length (getf native :panes)))
                 (when (> total-panes max-panes)
                   (fail-document
                    (format nil "Workspace contains more than ~D panes" max-panes)
                    :path (document-path+ path "windows") :limit :max-panes))
                 (setf (aref windows index) native)
              finally (return windows)))))))

(defun parse-workspace
    (source
     &key
       (max-input-bytes +default-max-input-bytes+)
       (max-depth +default-max-depth+)
       (max-nodes +default-max-nodes+)
       (max-string-length +default-max-string-length+)
       (max-windows +default-max-windows+)
       (max-panes +default-max-panes+)
       (max-argv +default-max-argv+)
       (max-environment +default-max-environment+)
       (max-integer-digits +default-max-integer-digits+))
  "Parse one bounded libtmux.lisp.workspace/1 JSON string into a WORKSPACE.
The complete document uses a closed grammar, rejects duplicate members, and
never interns or evaluates external names. Limits bound UTF-8 bytes, nesting,
nodes, strings, windows, total panes, argv length, session environment pairs
(MAX-ENVIRONMENT, default 256), and integer token digits. Pane shell_command is
explicit shell source; window layout accepts a named string or a custom object.
Input and retained values are copied. Signals INVALID-WORKSPACE-DOCUMENT or
WORKSPACE-LIMIT-EXCEEDED with WORKSPACE-PATH and WORKSPACE-LIMIT diagnostics.

See also: READ-WORKSPACE, MAKE-WORKSPACE, WORKSPACE-DATA."
  (unless (stringp source)
    (fail-document "PARSE-WORKSPACE requires a complete JSON string"))
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
  (let ((document (parse-json-events source max-depth max-nodes max-string-length)))
    (closed-object document '("schema" "session") #() "Workspace")
    (let ((schema (required-member document "schema" #())))
      (unless (and (stringp schema) (string= schema +schema+))
        (fail-document "Unsupported workspace-document schema" :path #("schema")))
      (let ((native
              (list :schema (copy-seq +schema+)
                    :session
                    (wire-session (required-member document "session" #())
                                  #("session") max-windows max-panes max-argv max-environment))))
        (handler-case
            (make-workspace native :max-windows max-windows
                                   :max-panes max-panes :max-argv max-argv
                                   :max-environment max-environment)
          (invalid-workspace-document (condition) (error condition))
          (invalid-workspace (cause)
            (fail-document "The workspace document violates the native workspace contract"
                           :cause cause)))))))

(defun read-workspace
    (path
     &rest options
     &key (max-input-bytes +default-max-input-bytes+)
     &allow-other-keys)
  "Read one bounded regular UTF-8 JSON file and return an owned WORKSPACE.
PATH is opened for input and never modified. MAX-INPUT-BYTES is enforced on
bytes read even if the file changes after opening. The descriptor is opened
nonblocking, then directories and special files are rejected before reading.
Other OPTIONS are forwarded to PARSE-WORKSPACE. Signals
INVALID-WORKSPACE-DOCUMENT or WORKSPACE-LIMIT-EXCEEDED and closes the stream.

See also: PARSE-WORKSPACE, WORKSPACE-DATA."
  (checked-limit max-input-bytes :max-input-bytes 1)
  (handler-case
      (let ((stream nil))
        (unwind-protect
             (progn
               #+sbcl
               (let ((descriptor
                       (sb-posix:open (namestring (pathname path))
                                      (logior sb-posix:o-rdonly
                                              sb-posix:o-nonblock #o2000000))))
                 (handler-case
                     (let ((status (sb-posix:fstat descriptor)))
                       (unless (sb-posix:s-isreg (sb-posix:stat-mode status))
                         (fail-document "Workspace path must name a regular file"))
                       (when (> (sb-posix:stat-size status) max-input-bytes)
                         (fail-document
                          (format nil "Workspace file exceeds ~D bytes" max-input-bytes)
                          :limit :max-input-bytes))
                       (setf stream
                             (sb-sys:make-fd-stream
                              descriptor :input t :element-type '(unsigned-byte 8)
                              :buffering :full :auto-close t :file path))
                       (setf descriptor nil))
                   (error (condition)
                     (when descriptor (sb-posix:close descriptor))
                     (error condition))))
               #-sbcl
               (setf stream (open path :direction :input
                                       :element-type '(unsigned-byte 8)))
               (let* ((buffer (make-array (1+ max-input-bytes)
                                          :element-type '(unsigned-byte 8)))
                      (count (read-sequence buffer stream)))
                 (when (> count max-input-bytes)
                   (fail-document
                    (format nil "Workspace file exceeds ~D bytes" max-input-bytes)
                    :limit :max-input-bytes))
                 (let ((source
                         (handler-case
                             #+sbcl (sb-ext:octets-to-string
                                     buffer :start 0 :end count :external-format :utf-8)
                             #-sbcl (map 'string #'code-char (subseq buffer 0 count))
                           (error (cause)
                             (fail-document "Workspace file is not valid UTF-8"
                                            :cause cause)))))
                   (apply #'parse-workspace source options))))
          (when stream (close stream))))
    (workspace-error (condition) (error condition))
    (error (cause)
      (fail-document "Cannot read the workspace file" :cause cause))))

(defstruct (apply-state (:constructor make-apply-state (&key session window)))
  session window)

(defparameter *fetch-snapshot-function* #'libtmux:fetch-snapshot)
(defparameter *execute-step-function* nil)

(defun operation-options (cancel-token timeout timeout-p output-limit output-limit-p)
  (append (when cancel-token (list :cancel-token cancel-token))
          (when timeout-p (list :timeout timeout))
          (when output-limit-p (list :output-limit output-limit))))

(defun required-outcome-value (outcome type description)
  (unless (typep outcome 'libtmux:command-outcome)
    (error 'libtmux:incomplete-snapshot
           :message "Workspace executor did not return a command outcome"))
  (unless (eq :succeeded (libtmux:outcome-status outcome))
    (error 'libtmux:command-failed :message "Workspace step did not succeed"
           :outcome outcome))
  (multiple-value-bind (value present-p) (libtmux:outcome-value outcome)
    (unless (and present-p (typep value type))
      (error 'libtmux:incomplete-snapshot
             :message (format nil "~A did not return a replacement observation" description)
             :cause (libtmux:outcome-observation-error outcome)
             :outcome outcome))
    value))

(defun state-with-window (state window outcome)
  (let ((link
          (find (apply-state-session state) (libtmux:window-links window)
                :key #'libtmux:session :test #'libtmux:same-entity-p)))
    (unless link
      (error 'libtmux:incomplete-snapshot
             :message "Workspace replacement window lacks its declared session link"
             :outcome outcome))
    (make-apply-state :session (libtmux:session link) :window window)))

(defun matching-state-link (state)
  (or (find (apply-state-session state)
            (libtmux:window-links (apply-state-window state))
            :key #'libtmux:session :test #'libtmux:same-entity-p)
      (error 'libtmux:incomplete-snapshot
             :message "Workspace window lacks its current session link")))

(defun ensure-step-window (state data)
  (unless (and state (apply-state-window state)
               (string= (getf data :window-name)
                        (libtmux:name (apply-state-window state))))
    (error 'libtmux:incomplete-snapshot
           :message "Workspace execution state does not match the planned window")))

(defun step-creation-options (data)
  (loop for key in '(:cwd :command :shell-command :environment)
        append (multiple-value-bind (value present-p) (plist-value data key)
                 (when present-p (list key value)))))

(defun execute-core-step (step client state options)
  (let ((action (step-action step))
        (data (step-data step)))
    (ecase action
      (:create-session
       (let* ((arguments
                (append (list :name (getf data :session-name)
                              :window-name (getf data :window-name))
                        (step-creation-options data)
                        options))
              (outcome (apply #'libtmux:new-session client arguments))
              (session (required-outcome-value outcome 'libtmux:session
                                               "Session creation"))
              (windows (libtmux:windows session))
              (window (find (getf data :window-name) windows
                            :key #'libtmux:name :test #'string=)))
         (unless (and window (= 1 (length windows)))
           (error 'libtmux:incomplete-snapshot
                  :message "Created session does not contain exactly its declared first window"
                  :outcome outcome))
         (values outcome (make-apply-state :session session :window window))))
      (:move-window
       (ensure-step-window state data)
       (let ((current (matching-state-link state)))
         (if (= (libtmux:index current) (getf data :index))
             (values nil state)
             (let* ((outcome
                      (apply #'libtmux:move-window client current
                             (apply-state-session state) (getf data :index) options))
                    (link (required-outcome-value outcome 'libtmux:window-link
                                                  "Window move")))
               (values outcome
                       (make-apply-state :session (libtmux:session link)
                                         :window (libtmux:window link)))))))
      (:create-window
       (let* ((arguments
                (append (list :name (getf data :window-name))
                        (multiple-value-bind (index present-p) (plist-value data :index)
                          (when present-p (list :index index)))
                        (step-creation-options data)
                        options))
              (outcome
                (apply #'libtmux:new-window client (apply-state-session state) arguments))
              (window (required-outcome-value outcome 'libtmux:window
                                              "Window creation")))
         (values outcome (state-with-window state window outcome))))
      (:split-pane
       (ensure-step-window state data)
       (let* ((panes (libtmux:panes (apply-state-window state)))
              (target (ecase (getf data :target)
                        (:first (aref panes 0))
                        (:last (aref panes (1- (length panes))))))
              (declared-direction (getf data :direction))
              (direction
                (if (eq declared-direction :adaptive)
                    (if (>= (libtmux:width target) (libtmux:height target))
                        :horizontal
                        :vertical)
                    declared-direction))
              (arguments
                (append
                 (list :direction direction)
                 (step-creation-options data)
                 options))
              (outcome (apply #'libtmux:split-pane client target arguments))
              (pane (required-outcome-value outcome 'libtmux:pane "Pane split")))
         (values outcome (state-with-window state (libtmux:window pane) outcome))))
      (:select-layout
       (ensure-step-window state data)
       (let* ((outcome
                (apply #'libtmux:select-layout client (apply-state-window state)
                       (getf data :layout) options))
              (window (required-outcome-value outcome 'libtmux:window
                                              "Layout selection")))
         (values outcome (state-with-window state window outcome)))))))

(setf *execute-step-function* #'execute-core-step)

(defun apply-failure (cause client step outcomes)
  (let* ((cause-outcome
           (and (typep cause 'libtmux:libtmux-error)
                (libtmux:error-outcome cause)))
         (retained
           (if (and cause-outcome
                    (not (find cause-outcome outcomes :test #'eq)))
               (cons cause-outcome outcomes)
               outcomes)))
    (error 'workspace-apply-failed
           :message (if step
                        "Workspace application stopped at a planned step"
                        "Workspace application stopped during final verification")
           :cause cause :outcome cause-outcome :client client :step step
           :outcomes (coerce (nreverse retained) 'simple-vector))))

(defun check-workspace-deadline (client deadline)
  (when deadline
    (let ((remaining (- deadline (libtmux.internal::monotonic-seconds))))
      (unless (plusp remaining)
        (error 'workspace-deadline-exceeded :client client :limit :total-timeout
               :message "Workspace application exhausted its total time budget"))
      remaining)))

(defun workspace-call-options (client options deadline)
  (if deadline
      (let ((result (copy-list options)))
        (setf (getf result :timeout)
              (min (check-workspace-deadline client deadline)
                   (getf options :timeout (slot-value client 'libtmux::timeout))))
        result)
      options))

(defun apply-workspace
    (client workspace
     &key cancel-token (timeout nil timeout-p) (output-limit nil output-limit-p)
       (total-timeout nil total-timeout-p))
  "Create or reuse WORKSPACE through explicit CLIENT and return WORKSPACE-RESULT.
The function first calls FETCH-SNAPSHOT and PLAN-WORKSPACE. A proven match
returns immediately with no command outcomes. A missing session executes each
planned core mutation once, in order, then captures and proves the final
topology. TIMEOUT and OUTPUT-LIMIT, when supplied, apply separately to each core
operation; CANCEL-TOKEN is shared. Conflicts dispatch no mutation.

TOTAL-TIMEOUT, when supplied, is a nonnegative finite number of seconds shared
across the application. Each acquisition and core step receives the smaller of
its remaining total budget and TIMEOUT or the client's default. The budget is
also checked after initial and final planning. Zero refuses the initial read;
omission adds no application budget. OUTPUT-LIMIT remains per operation.

This budget controls admission at workspace boundaries. Preparation before a
core timer starts, synchronous platform calls and additive cleanup can let an
admitted core call run or dispatch past it; caller wall time is not bounded.
Boundary expiry before the first core-step invocation signals
WORKSPACE-DEADLINE-EXCEEDED directly. Execution begins with that invocation,
which can itself fail before dispatch. Later expiry becomes WORKSPACE-APPLY-FAILED's cause,
retaining completed outcomes. It does not imply an uncertain command effect.

Failure within a core step or later signals WORKSPACE-APPLY-FAILED. RESULT-OUTCOMES retains
every dispatched outcome, including one whose post-command observation cannot
advance workspace state; FAILED-STEP identifies the failed or unstarted next
step. Final-verification failure has no failed step. No rollback or automatic
retry occurs.

See also: PLAN-WORKSPACE, RESULT-SNAPSHOT, RESULT-OUTCOMES, FAILED-STEP,
WORKSPACE-DEADLINE-EXCEEDED."
  (check-type client libtmux:client)
  (check-type workspace workspace)
  (when total-timeout-p
    (let ((limit (if output-limit-p output-limit
                     (slot-value client 'libtmux::output-limit))))
      (libtmux.internal::check-limits total-timeout limit)
      (libtmux.internal::check-limits
       (if timeout-p timeout (slot-value client 'libtmux::timeout)) limit)))
  (let* ((deadline (when total-timeout-p
                     (+ (libtmux.internal::monotonic-seconds) total-timeout)))
         (options (operation-options cancel-token timeout timeout-p
                                     output-limit output-limit-p))
         (initial (apply *fetch-snapshot-function* client
                         (workspace-call-options client options deadline)))
         (steps (plan-steps (plan-workspace workspace initial))))
    (check-workspace-deadline client deadline)
    (when (zerop (length steps))
      (return-from apply-workspace
        (make-instance 'workspace-result :snapshot initial
                                         :outcomes #() :created-p nil)))
    (let ((state nil) (outcomes nil) (started-p nil))
      (loop for step across steps
            do (handler-case
                   (let ((step-options (workspace-call-options client options deadline)))
                     (setf started-p t)
                     (multiple-value-bind (outcome next-state)
                         (funcall *execute-step-function* step client state step-options)
                       (when outcome (push outcome outcomes))
                       (setf state next-state)))
                 (error (cause)
                   (if started-p
                       (apply-failure cause client step outcomes)
                       (error cause)))))
      (handler-case
          (let* ((final (apply *fetch-snapshot-function* client
                               (workspace-call-options client options deadline)))
                 (remaining (plan-steps (plan-workspace workspace final))))
            (check-workspace-deadline client deadline)
            (unless (zerop (length remaining))
              (error 'libtmux:incomplete-snapshot
                     :message "Workspace session is absent after completed mutations"))
            (make-instance 'workspace-result :snapshot final
                                             :outcomes (coerce (nreverse outcomes)
                                                               'simple-vector)
                                             :created-p t))
        (error (cause)
          (apply-failure cause client nil outcomes))))))
