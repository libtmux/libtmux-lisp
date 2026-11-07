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
   #:workspace-apply-failed
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
  (:documentation "Return the WORKSPACE-STEP that failed, or NIL before execution.

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

(defmethod workspace-path ((condition workspace-error))
  (deep-copy (slot-value condition 'path)))

(defmethod workspace-limit ((condition workspace-error))
  (slot-value condition 'limit))

(defmethod failed-step ((condition workspace-apply-failed))
  (slot-value condition 'step))

(defstruct (pane-spec (:constructor %make-pane-spec (&key cwd cwd-p command command-p)))
  cwd cwd-p command command-p)

(defstruct (window-spec
            (:constructor %make-window-spec
                (&key name index index-p cwd cwd-p layout layout-p panes)))
  name index index-p cwd cwd-p layout layout-p panes)

(defstruct (session-spec (:constructor %make-session-spec (&key name cwd cwd-p windows)))
  name cwd cwd-p windows)

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
               (fail-workspace (format nil "~S is not allowed in ~A" key description)
                               :path (path+ path key)))
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

(defun normalize-pane (data path max-argv)
  (closed-plist data '(:cwd :command) path "Pane")
  (multiple-value-bind (cwd cwd-p) (plist-value data :cwd)
    (multiple-value-bind (command command-p) (plist-value data :command)
      (%make-pane-spec
       :cwd (when cwd-p (owned-text cwd (path+ path :cwd) "Pane CWD"))
       :cwd-p cwd-p
       :command (when command-p
                  (normalized-command command (path+ path :command) max-argv))
       :command-p command-p))))

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
              (when (and layout-p (not (member layout +layouts+ :test #'eq)))
                (fail-workspace "Window layout must be a supported named-layout keyword"
                                :path (path+ path :layout)))
              (%make-window-spec
               :name (owned-text name (path+ path :name) "Window name")
               :index index :index-p index-p
               :cwd (when cwd-p (owned-text cwd (path+ path :cwd) "Window CWD"))
               :cwd-p cwd-p :layout layout :layout-p layout-p
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
            (list :command (deep-copy (pane-spec-command pane))))))

(defun window-data (window)
  (append (list :name (copy-seq (window-spec-name window)))
          (when (window-spec-index-p window) (list :index (window-spec-index window)))
          (when (window-spec-cwd-p window) (list :cwd (copy-seq (window-spec-cwd window))))
          (when (window-spec-layout-p window) (list :layout (window-spec-layout window)))
          (list :panes (map 'simple-vector #'pane-data (window-spec-panes window)))))

(defun normalized-data (session)
  (list :schema (copy-seq +schema+)
        :session
        (append (list :name (copy-seq (session-spec-name session)))
                (when (session-spec-cwd-p session)
                  (list :cwd (copy-seq (session-spec-cwd session))))
                (list :windows (map 'simple-vector #'window-data
                                    (session-spec-windows session))))))

(defun make-workspace (data &key (max-windows 100) (max-panes 1000) (max-argv 256))
  "Validate closed native DATA and return an owned WORKSPACE without I/O.
DATA is a keyword plist in schema libtmux.lisp.workspace/1. Lists and vectors
must be finite. MAX-WINDOWS, MAX-PANES, and MAX-ARGV bound retained topology and
commands. Unknown or duplicate keys, unsafe text, and shell-like command
strings signal INVALID-WORKSPACE. Input containers and strings are copied.

See also: WORKSPACE-DATA, PLAN-WORKSPACE, PARSE-WORKSPACE."
  (checked-limit max-windows :max-windows 1)
  (checked-limit max-panes :max-panes 1)
  (checked-limit max-argv :max-argv 0)
  (closed-plist data '(:schema :session) #() "Workspace")
  (multiple-value-bind (schema schema-p) (plist-value data :schema)
    (unless (and schema-p (stringp schema) (string= schema +schema+))
      (fail-workspace "Unsupported or missing workspace :SCHEMA" :path #(:schema)))
    (multiple-value-bind (session-data session-p) (plist-value data :session)
      (unless session-p
        (fail-workspace "Workspace :SESSION is required" :path #(:session)))
      (closed-plist session-data '(:name :cwd :windows) #(:session) "Session")
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
                          :name (owned-text name #(:session :name) "Session name")
                          :cwd (when cwd-p (owned-text cwd #(:session :cwd) "Session CWD"))
                          :cwd-p cwd-p :windows (coerce specs 'simple-vector)))
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
              (list :command (deep-copy (pane-spec-command pane)))))))

(defun first-pane-data (session window)
  (let* ((pane (aref (window-spec-panes window) 0))
         (cwd (effective-cwd pane window session)))
    (append (when cwd (list :cwd (copy-seq cwd)))
            (when (pane-spec-command-p pane)
              (list :command (deep-copy (pane-spec-command pane)))))))

(defun creation-steps (workspace)
  (let* ((session (slot-value workspace 'session))
         (windows (session-spec-windows session))
         (first (aref windows 0))
         (steps
           (list (apply #'make-step :create-session
                        :session-name (session-spec-name session)
                        :window-name (window-spec-name first)
                        (first-pane-data session first)))))
    (when (window-spec-index-p first)
      (setf steps
            (append steps
                    (list (make-step :move-window
                                     :window-name (window-spec-name first)
                                     :index (window-spec-index first))))))
    (loop for pane across (window-spec-panes first) for position from 0
          when (plusp position)
            do (setf steps
                     (append steps
                             (list (apply #'make-step :split-pane
                                          (pane-step-data session first pane position))))))
    (when (window-spec-layout-p first)
      (setf steps
            (append steps (list (make-step :select-layout
                                           :window-name (window-spec-name first)
                                           :layout (window-spec-layout first))))))
    (loop for window across windows for window-position from 0
          when (plusp window-position)
            do (setf steps
                     (append steps
                             (list
                              (apply #'make-step :create-window
                                     :window-name (window-spec-name window)
                                     (append
                                      (when (window-spec-index-p window)
                                        (list :index (window-spec-index window)))
                                      (first-pane-data session window))))))
               (loop for pane across (window-spec-panes window) for position from 0
                     when (plusp position)
                       do (setf steps
                                (append steps
                                        (list (apply #'make-step :split-pane
                                                     (pane-step-data session window pane position))))))
               (when (window-spec-layout-p window)
                 (setf steps
                       (append steps (list (make-step :select-layout
                                                      :window-name (window-spec-name window)
                                                      :layout (window-spec-layout window)))))))
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
are not inferred from mutable live state. No tmux I/O occurs.

See also: PLAN-STEPS, WORKSPACE-DATA, APPLY-WORKSPACE."
  (check-type workspace workspace)
  (when snapshot (check-type snapshot libtmux:snapshot))
  (let* ((session-spec (slot-value workspace 'session))
         (session (and snapshot (matching-session snapshot (session-spec-name session-spec)))))
    (make-instance 'workspace-plan
                   :steps (if session
                              (progn (prove-topology workspace session) #())
                              (creation-steps workspace)))))
