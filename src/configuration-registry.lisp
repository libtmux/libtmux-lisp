(in-package #:libtmux.internal)

(defstruct (option-spec (:constructor %make-option-spec))
  "One private immutable source contract, shared only where versions agree."
  (name nil :read-only t) (kind nil :read-only t) (representation nil :read-only t)
  (scopes nil :read-only t) (flags nil :read-only t)
  (array-p nil :read-only t) (hook-p nil :read-only t)
  (minimum nil :read-only t) (maximum nil :read-only t) (choices nil :read-only t)
  (separator nil :read-only t) (pattern nil :read-only t)
  (pattern-language nil :read-only t) (unit nil :read-only t))

(defstruct (option-catalog (:constructor %make-option-catalog))
  "One exact tmux source pin's ordered contracts, aliases and capabilities."
  (version nil :read-only t) (commit nil :read-only t)
  (options nil :read-only t) (by-name nil :read-only t)
  (aliases nil :read-only t) (source-lines nil :read-only t)
  (formatted-p nil :read-only t) (string-keys-p nil :read-only t)
  (numeric-key-maximum nil :read-only t) (user-event-hooks-p nil :read-only t))

(define-condition option-catalog-unavailable (libtmux:libtmux-error)
  ((version :initarg :version :initform nil))
  (:documentation "The live tmux release has no reviewed configuration schema."))

(defparameter *configuration-scopes*
  '(:server :global-session :session :global-window :window :pane))

(defparameter *option-catalogs*
  (let ((contracts (map 'vector (lambda (data) (apply #'%make-option-spec data))
                       *option-contract-data*))
        (catalogs (make-hash-table :test 'equal)))
    (dolist (record *option-catalog-data* catalogs)
      (destructuring-bind (version commit ids lines alias-data capabilities) record
        (let ((options (map 'vector (lambda (id) (aref contracts id)) ids))
              (names (make-hash-table :test 'equal))
              (aliases (make-hash-table :test 'equal))
              (locations (make-hash-table :test 'equal)))
          (loop for spec across options for line in lines
                do (setf (gethash (option-spec-name spec) names) spec
                         (gethash (option-spec-name spec) locations) line))
          (dolist (alias alias-data)
            (setf (gethash (first alias) aliases) (second alias)))
          (setf (gethash version catalogs)
                (apply #'%make-option-catalog :version version :commit commit
                       :options options :by-name names :aliases aliases :source-lines locations
                       capabilities)))))))

(defun configuration-catalog (version)
  "Resolve exactly VERSION's private immutable catalog, without tmux I/O.
Never select a neighboring release or silently widen the supported schema."
  (or (and (stringp version) (gethash version *option-catalogs*))
      (error 'option-catalog-unavailable :version version
             :message (format nil "No reviewed configuration schema for tmux ~S" version))))

(defun check-configuration-scope (scope)
  (unless (member scope *configuration-scopes*)
    (invalid-argument "Configuration scope must be one of ~S" *configuration-scopes*))
  scope)

(defun catalog-option-names (catalog &key scope hooks-only)
  "Return owned canonical names in source order, optionally restricted by scope.
Aliases do not duplicate discovery entries. Dynamic user names are not enumerated."
  (when scope (check-configuration-scope scope))
  (coerce (loop for spec across (option-catalog-options catalog)
                when (and (or (null scope) (member scope (option-spec-scopes spec)))
                          (or (null hooks-only) (option-spec-hook-p spec)))
                  collect (copy-seq (option-spec-name spec))) 'simple-vector))

(defun catalog-option (catalog name scope &key hooks-only)
  "Resolve a full option name or declared alias in SCOPE before payload dispatch.
User @ values are strings, including 3.8's dynamic event source. A named read
does not prove that an event was registered. Static contracts remain private."
  (check-configuration-scope scope)
  (let* ((name (text-argument name "Option name" nil))
         (canonical (or (gethash name (option-catalog-aliases catalog)) name))
         (spec (gethash canonical (option-catalog-by-name catalog))))
    (cond
      ((and (char= #\@ (char name 0)) (null spec))
       (when (and hooks-only (eq scope :server))
         (invalid-argument "Hook commands cannot address the server option table"))
       (when (and hooks-only (not (option-catalog-user-event-hooks-p catalog)))
         (invalid-argument "This tmux schema does not support dynamic @ event hooks"))
       (%make-option-spec :name name :kind :string :representation :string
                          :scopes (if hooks-only (remove :server *configuration-scopes*)
                                      *configuration-scopes*)))
      ((and spec (member scope (option-spec-scopes spec))
            (or (null hooks-only) (option-spec-hook-p spec))) spec)
      (t (invalid-argument "Option ~S is unavailable for scope ~S in tmux ~A~A"
                           name scope (option-catalog-version catalog)
                           (if hooks-only " hook schema" ""))))))

(defun normalize-option-value (spec value)
  "Validate one scalar/array-entry operand and own mutable values.
Keys, colours, styles and command source remain text; tmux validates its own
text dialects. Native numbers use exact catalog bounds, not a host word width."
  (case (option-spec-kind spec)
    (:number
     (unless (and (integerp value)
                  (<= (option-spec-minimum spec) value (option-spec-maximum spec)))
       (invalid-argument "Option ~A expects an integer from ~D through ~D"
                         (option-spec-name spec) (option-spec-minimum spec) (option-spec-maximum spec)))
     value)
    (:flag
     (unless (or (eq value t) (null value))
       (invalid-argument "Option ~A expects T or NIL" (option-spec-name spec)))
     value)
    (:choice
     (unless (and (stringp value) (member value (option-spec-choices spec) :test #'string=))
       (invalid-argument "Option ~A expects one of ~S"
                         (option-spec-name spec) (option-spec-choices spec)))
     (copy-seq value))
    ((:string :key :colour :command) (text-argument value (option-spec-name spec)))
    (otherwise (error 'option-catalog-unavailable
                      :message "The option registry contains an unsupported value kind"))))

(defun normalize-option-key (catalog key)
  "Return canonical decimal or owned string key text for the exact live schema.
Numeric strings in 3.8 normalize like tmux; nonnumeric strings retain their
text. Do not allocate a collection indexed by the resulting number."
  (let ((maximum (option-catalog-numeric-key-maximum catalog)))
    (when (integerp key)
      (return-from normalize-option-key (integer-argument key 0 maximum "Array key")))
    (unless (option-catalog-string-keys-p catalog)
      (invalid-argument "This tmux schema requires an integer array key"))
    (let ((text (text-argument key "Array key" nil)))
      (if (every (lambda (character) (char<= #\0 character #\9)) text)
          (let ((start (position-if (lambda (character) (char/= character #\0)) text)))
            (if (null start) (make-string 1 :initial-element #\0)
                (let ((digits (- (length text) start)))
                  (when (> digits (length (write-to-string maximum :base 10 :radix nil)))
                    (invalid-argument "Numeric array key exceeds ~D" maximum))
                  (integer-argument (parse-integer text :start start) 0 maximum "Array key"))))
          text))))
