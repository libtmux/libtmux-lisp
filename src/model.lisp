(in-package #:libtmux)

(defgeneric entity-model (entity)
  (:documentation "Return :SESSION, :WINDOW, :PANE, :WINDOW-LINK or :CLIENT. No I/O.
:CLIENT denotes an attached tmux client observation, not a connection scope."))

(defclass snapshot ()
  ((context :initarg :context)
   (generation :initarg :generation)
   (reference :initform (gensym "CAPTURE-"))
   (provenance :initarg :provenance)
   (collections :initform (make-hash-table :test 'eq)))
  (:documentation "A finite captured graph assembled over a recorded acquisition interval.
It contains owned observations, not a transactional view of a changing daemon.
Public accessors are local and return fresh mutable values."))

(defclass entity ()
  ((snapshot :initarg :snapshot)
   (model :initarg :model :reader entity-model)
   (identity :initarg :identity)
   (fields :initarg :fields)
   (relations :initform (make-hash-table :test 'eq)))
  (:documentation "An owned observation from one snapshot; construct through acquisition.
Private slot mutation is unsupported. Refresh returns another observation."))
(defclass session (entity) ()
  (:documentation "A captured physical tmux session.

A session is one observation from a snapshot. Calls that only read it take no
client, never contact tmux and keep working after the client closes. Calls
that change a session take a client first and the captured session next.

#### What is on here

Calls that take a session, or that return one, fall into these groups:

**Finding sessions.** `libtmux:fetch-sessions` captures a fresh snapshot and
returns every session in it, while `libtmux:sessions` reads them from a
snapshot you already hold. `libtmux:session/function` returns the session that
a window link or an attached client belongs to. `libtmux:refresh` returns the
same session from a new capture and signals `libtmux:stale-target` when it has
gone.

`libtmux:fetch-sessions`, `libtmux:sessions`, `libtmux:session/function` and
`libtmux:refresh`

**Reading what a capture recorded.** `libtmux:name` returns the captured name
and whether the capture had one, and `libtmux:id` returns the tmux identity, a
string such as `$0`. `libtmux:field-value` reaches any other registered field,
such as the creation time, the attached count and the window link count, and
`libtmux:entity-data` returns every captured field as a fresh plist.
`libtmux:entity-model` names the kind of entity,
`libtmux:provenance` reports the capture it came from, and
`libtmux:same-entity-p` compares identity, not field values. None of them
contacts tmux.

`libtmux:name`, `libtmux:id`, `libtmux:field-value`, `libtmux:entity-data`,
`libtmux:entity-model`, `libtmux:provenance` and `libtmux:same-entity-p`

**Walking to its windows and terminals.** `libtmux:windows` returns the
session's windows, one per link, so a window linked twice appears twice.
`libtmux:window-links` returns the links, each with an index and an active
flag, and `libtmux:clients` returns the terminals attached to the session.

`libtmux:windows`, `libtmux:window-links` and `libtmux:clients`

**Creating, renaming and removing.** `libtmux:new-session` creates a detached
session on a daemon that is already running; it never starts or replaces one,
and `libtmux:outcome-value` supplies the new session from the result.
`libtmux:new-window` adds a window to a captured session, and
`libtmux:rename-session` renames one, with tmux enforcing its name
restrictions and uniqueness. `libtmux:kill-session` deletes exactly the
captured session after checking its live identity, and never retries.

`libtmux:new-session`, `libtmux:new-window`, `libtmux:rename-session`,
`libtmux:kill-session` and `libtmux:outcome-value`

**Placing windows.** `libtmux:move-window` moves a window link into the
session at a free index, `libtmux:link-window` links a window there as well,
and `libtmux:break-pane` breaks a pane out into a free index of the session.
None of them overwrites an occupied index.

`libtmux:move-window`, `libtmux:link-window` and `libtmux:break-pane`

**Selecting windows and terminals.** `libtmux:next-window`,
`libtmux:previous-window` and `libtmux:last-window` select a window link in the
session, and `libtmux:last-window` signals an error when tmux has no last
window. `libtmux:switch-client` points an attached terminal at the session, and
`libtmux:lock-session` asks the session's attached terminals to run their lock
command. A lock call's success acknowledges the request, not the terminal's
reaction.

`libtmux:next-window`, `libtmux:previous-window`, `libtmux:last-window`,
`libtmux:switch-client` and `libtmux:lock-session`

**Options, hooks and environment.** Give each call `:scope :session` and the
captured session as `:target`. `libtmux:set-option` and `libtmux:unset-option`
write or clear one option, `libtmux:show-option` and `libtmux:show-options`
return decoded values, and `libtmux:show-options-text` returns tmux's printer
text. `libtmux:set-hook`, `libtmux:unset-hook`, `libtmux:show-hooks` and
`libtmux:show-hooks-text` do the same for hooks, and `libtmux:set-environment`,
`libtmux:unset-environment`, `libtmux:remove-environment`,
`libtmux:show-environment` and `libtmux:show-environment-text` do it for the
session's environment table.

`libtmux:set-option`, `libtmux:unset-option`, `libtmux:show-option`,
`libtmux:show-options`, `libtmux:show-options-text`, `libtmux:set-hook`,
`libtmux:unset-hook`, `libtmux:show-hooks`, `libtmux:show-hooks-text`,
`libtmux:set-environment`, `libtmux:unset-environment`,
`libtmux:remove-environment`, `libtmux:show-environment` and
`libtmux:show-environment-text`

**Messages and control connections.** `libtmux:display-message` prints a
message in the context of a captured session, and expands tmux formats only
when you ask. `libtmux.control:open-connection` and
`libtmux.control:with-connection` attach a separate control connection to a
captured session, which needs a daemon at tmux 3.8 or newer.

`libtmux:display-message`, `libtmux.control:open-connection` and
`libtmux.control:with-connection`

**Filtering sessions.** The separately loaded `libtmux/query` system filters
captured sessions locally. `libtmux.query:compile-filter` compiles a filter
form for the `:session` model without evaluating it as Lisp, and
`libtmux.query:matching` returns the sessions that it accepts.
`libtmux.query:one` and `libtmux.query:one-or-none` take the single result.
`libtmux.query:from` copies sessions into a query set, `libtmux.query:where`,
`libtmux.query:where-if` and `libtmux.query:order-by` narrow and order it,
`libtmux.query:items` returns its members, and `libtmux.query:fields` lists the
fields that a session filter can name.

`libtmux.query:compile-filter`, `libtmux.query:matching`, `libtmux.query:one`,
`libtmux.query:one-or-none`, `libtmux.query:from`, `libtmux.query:where`,
`libtmux.query:where-if`, `libtmux.query:order-by`, `libtmux.query:items` and
`libtmux.query:fields`"))
(defclass window (entity) () (:documentation "A physical window shared by zero or more captured links."))
(defclass pane (entity) () (:documentation "A physical pane belonging to one captured window."))
(defclass window-link (entity) ()
  (:documentation "A captured session/index locator with its expected physical window ID."))
(defclass attached-client (entity) ()
  (:documentation "One captured attached-tmux-client row; identity is observation-scoped."))

(defgeneric field-value (entity field)
  (:documentation "Return a captured field and presence as two values, without I/O.
Present false is NIL,T; absence is NIL,NIL. Strings and relation containers are
copied. Unknown fields and unloaded relations signal FIELD-UNAVAILABLE."))
(defgeneric entity-data (entity)
  (:documentation "Return a fresh finite plist of captured fields and provenance.
Relationships contain identifiers, not operational handles. Absent optional
fields are omitted; present false values remain in the plist. No tmux I/O."))
(defgeneric id (entity)
  (:documentation "Return the captured identity, copying mutable components. No I/O.
Physical IDs are strings; a link ID is (session-ID index window-ID). Attached
client IDs identify rows within a single observation, not stable daemon clients."))
(defgeneric provenance (observation)
  (:documentation "Return fresh captured provenance and acquisition bounds, without I/O."))
(defgeneric sessions (snapshot)
  (:documentation "Return a fresh vector of physical sessions in captured wire order. No I/O."))
(defgeneric windows (observation)
  (:documentation "Return a fresh vector of captured windows, without I/O.
Snapshot windows are physical entities in first-occurrence order. Session
windows contain one item per link and preserve repeated physical windows."))
(defgeneric panes (observation)
  (:documentation "Return a fresh vector of captured physical panes, without I/O.
Snapshots preserve first occurrence; windows preserve the captured pane order."))
(defgeneric window-links (observation)
  (:documentation "Return every captured window link in wire order as a fresh vector. No I/O."))
(defgeneric clients (observation)
  (:documentation "Return a fresh vector of attached-client observations, without I/O.
Preserve listing order and multiplicity, including repeated target names."))
(defgeneric window (entity)
  (:documentation "Return the locally captured physical window of a pane or link."))
(defgeneric session (entity)
  (:documentation "Return the locally captured session of a link or attached client."))

(defmethod print-object ((snapshot snapshot) stream)
  (print-unreadable-object (snapshot stream :type t :identity t)
    (format stream "generation ~D" (slot-value snapshot 'generation))))
(defmethod print-object ((entity entity) stream)
  (print-unreadable-object (entity stream :type t)
    (prin1 (slot-value entity 'identity) stream)))

(in-package #:libtmux.internal)

(defun owned-data (value)
  (typecase value
    (string (copy-seq value))
    (cons (cons (owned-data (car value)) (owned-data (cdr value))))
    (vector (map 'vector #'owned-data value))
    (t value)))

(defun resolved-field-value (entity registry)
  (let ((field (field-spec-key registry))
        (model (libtmux:entity-model entity)))
    (unless (eq model (field-spec-model registry))
      (error 'libtmux:field-unavailable :field field :model model
             :message (format nil "Field ~S is not registered for model ~S" field model)))
    (if (eq (field-spec-kind registry) :relation)
        (multiple-value-bind (value loaded)
            (gethash field (slot-value entity 'libtmux::relations))
          (unless loaded
            (error 'libtmux:field-unavailable :field field :model model
                   :message (format nil "Relation ~S was not loaded in this capture" field)))
          (values value (if (eq (field-spec-cardinality registry) :many) t (not (null value)))))
        (multiple-value-bind (value present-p)
            (gethash field (slot-value entity 'libtmux::fields))
          (when (and (not present-p) (not (field-spec-optional registry)))
            (error 'libtmux:field-unavailable :field field :model model
                   :message (format nil "Required field ~S is missing from the capture" field)))
          (values value present-p)))))

(defun raw-field-value (entity field)
  (resolved-field-value entity (registered-field field (libtmux:entity-model entity))))

(defun captured-collection (snapshot model)
  (copy-seq (gethash model (slot-value snapshot 'libtmux::collections) #())))

(defun entity-reference (entity)
  (list :model (libtmux:entity-model entity) :id (libtmux:id entity)))

(in-package #:libtmux)

(defmethod field-value ((entity entity) field)
  (multiple-value-bind (value present) (libtmux.internal::raw-field-value entity field)
    (values (if (or (stringp value) (vectorp value)) (copy-seq value) value) present)))
(defmethod id ((entity entity))
  (libtmux.internal::owned-data (slot-value entity 'identity)))
(defmethod provenance ((snapshot snapshot))
  (append (list :context (copy-seq (symbol-name (slot-value snapshot 'context)))
                :generation (slot-value snapshot 'generation)
                :observation (copy-seq (symbol-name (slot-value snapshot 'reference))))
          (libtmux.internal::owned-data (slot-value snapshot 'provenance))))
(defmethod provenance ((entity entity)) (provenance (slot-value entity 'snapshot)))
(defmethod entity-data ((entity entity))
  (append
   (list :libtmux/model (entity-model entity) :libtmux/id (id entity)
         :libtmux/provenance (provenance entity))
   (loop for field in (libtmux.internal::model-fields (entity-model entity))
         append (multiple-value-bind (value present)
                    (field-value entity (libtmux.internal::field-spec-key field))
                  (when present
                    (list (libtmux.internal::field-spec-key field)
                          (if (eq :relation (libtmux.internal::field-spec-kind field))
                              (if (eq :many (libtmux.internal::field-spec-cardinality field))
                                  (map 'vector #'libtmux.internal::entity-reference value)
                                  (libtmux.internal::entity-reference value))
                              value)))))))

(defun same-entity-p (left right)
  "Compare captured identity, not captured field values. No I/O.
Context and generation must agree. Link comparison retains its expected window
and index. Attached clients compare equal only within their original capture."
  (and (typep left 'entity) (typep right 'entity)
       (let ((a (slot-value left 'snapshot)) (b (slot-value right 'snapshot)))
         (and (eq (entity-model left) (entity-model right))
              (eq (slot-value a 'context) (slot-value b 'context))
              (= (slot-value a 'generation) (slot-value b 'generation))
              (or (not (typep left 'attached-client)) (eq a b))
              (equal (slot-value left 'identity) (slot-value right 'identity))))))

(defmethod sessions ((snapshot snapshot)) (libtmux.internal::captured-collection snapshot :session))
(defmethod windows ((snapshot snapshot)) (libtmux.internal::captured-collection snapshot :window))
(defmethod panes ((snapshot snapshot)) (libtmux.internal::captured-collection snapshot :pane))
(defmethod clients ((snapshot snapshot)) (libtmux.internal::captured-collection snapshot :client))
(defmethod window-links ((snapshot snapshot)) (libtmux.internal::captured-collection snapshot :window-link))
(defmethod window-links ((session session)) (field-value session :session/window-links))
(defmethod window-links ((window window)) (field-value window :window/links))
(defmethod clients ((session session)) (field-value session :session/clients))
(defmethod windows ((session session)) (map 'vector #'window (window-links session)))
(defmethod panes ((window window)) (field-value window :window/panes))
(defmethod window ((pane pane)) (field-value pane :pane/window))
(defmethod window ((link window-link)) (field-value link :link/window))
(defmethod session ((link window-link)) (field-value link :link/session))
(defmethod session ((client attached-client)) (field-value client :client/session))

(in-package #:libtmux.internal)

(defmacro define-captured-reader (name documentation &rest bindings)
  `(progn
     (defgeneric ,name (entity) (:documentation ,documentation))
     ,@(loop for (class field) in bindings
             collect `(defmethod ,name ((entity ,class)) (libtmux:field-value entity ,field)))))

(define-captured-reader libtmux:name "Return the captured name and presence, without I/O; text is copied."
  (libtmux:session :session/name) (libtmux:window :window/name) (libtmux:attached-client :client/name))
(define-captured-reader libtmux:active-p "Return captured active state and presence, without I/O. False is NIL,T."
  (libtmux:pane :pane/active) (libtmux:window-link :link/active))
(define-captured-reader libtmux:width "Return the positive captured width and presence, without I/O."
  (libtmux:pane :pane/width) (libtmux:window :window/width))
(define-captured-reader libtmux:height "Return the positive captured height and presence, without I/O."
  (libtmux:pane :pane/height) (libtmux:window :window/height))
(define-captured-reader libtmux:index "Return the nonnegative captured index and presence, without I/O."
  (libtmux:pane :pane/index) (libtmux:window-link :link/index))
(define-captured-reader libtmux:current-command "Return copied captured command text and presence, without I/O."
  (libtmux:pane :pane/current-command))
(define-captured-reader libtmux:current-path "Return copied captured path text and presence, without local pathname conversion."
  (libtmux:pane :pane/current-path))
(define-captured-reader libtmux:title "Return a copied captured pane title and presence; empty is present. No I/O."
  (libtmux:pane :pane/title))
(define-captured-reader libtmux:dead-p "Return tmux's captured dead flag and presence, without inferring it from PID."
  (libtmux:pane :pane/dead))
