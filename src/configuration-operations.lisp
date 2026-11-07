(in-package #:libtmux.internal)

(defun ascii-letter-p (character)
  (or (char<= #\A character #\Z) (char<= #\a character #\z)))

(defun ascii-digit-p (character)
  (char<= #\0 character #\9))

(defun checked-option-name (name)
  "Own NAME and restrict dynamic names to the reversible public write grammar."
  (let ((name (text-argument name "Option name" nil)))
    (when (char= (char name 0) #\@)
      (unless (and (> (length name) 1)
                   (loop for index from 1 below (length name)
                         for character = (char name index)
                         always (or (ascii-letter-p character)
                                    (ascii-digit-p character)
                                    (find character "_.-"))))
        (invalid-argument
         "User option names must match @[A-Za-z0-9_.-]+")))
    name))

(defun checked-environment-name (name)
  "Own NAME and enforce the public environment mutation grammar."
  (let ((name (text-argument name "Environment name" nil)))
    (unless (and (or (ascii-letter-p (char name 0))
                     (char= #\_ (char name 0)))
                 (loop for index from 1 below (length name)
                       for character = (char name index)
                       always (or (ascii-letter-p character)
                                  (ascii-digit-p character)
                                  (char= #\_ character))))
      (invalid-argument
       "Environment names must match [A-Za-z_][A-Za-z0-9_]*"))
    name))

(defun configuration-scope-data (scope target)
  "Return guarded targets and tmux flags for one explicit option table."
  (labels ((without-target (flags)
             (when target
               (invalid-argument "Scope ~S does not accept a target" scope))
             (values nil flags))
           (with-target (model flags)
             (unless target
               (invalid-argument "Scope ~S requires a captured ~A target" scope model))
             (let ((id (physical-target target model)))
               (values (list target) (append flags (list "-t" id))))))
    (case scope
      (:server (without-target '("-s")))
      (:global-session (without-target '("-g")))
      (:session (with-target :session nil))
      (:global-window (without-target '("-g" "-w")))
      (:window (with-target :window '("-w")))
      (:pane (with-target :pane '("-p")))
      (otherwise
       (invalid-argument
        "Option scope must be :SERVER, :GLOBAL-SESSION, :SESSION, :GLOBAL-WINDOW, :WINDOW or :PANE")))))

(defun environment-scope-data (scope target)
  "Return guarded targets and tmux flags for one raw environment table."
  (case scope
    (:global
     (when target (invalid-argument "Global environment scope does not accept a target"))
     (values nil '("-g")))
    (:session
     (unless target
       (invalid-argument "Session environment scope requires a captured session target"))
     (values (list target) (list "-t" (physical-target target :session))))
    (otherwise
     (invalid-argument "Environment scope must be :GLOBAL or :SESSION"))))

(defun configuration-value-text (spec value format-p)
  "Return one owned tmux value string under SPEC's declared native type."
  (if format-p
      (text-argument value "Option format")
      (let ((value (normalize-option-value spec value)))
        (case (option-spec-kind spec)
          (:number (write-to-string value :base 10 :radix nil))
          (:flag (if value "on" "off"))
          (otherwise value)))))

(defun configuration-option-reference (catalog spec name key key-p)
  "Return a literal option or array-element reference owned by the caller."
  (if key-p
      (progn
        (unless (option-spec-array-p spec)
          (invalid-argument "Option ~A is not an array" (option-spec-name spec)))
        (let ((key (normalize-option-key catalog key)))
          (when (and (stringp key) (find #\] key))
            (invalid-argument "Array keys cannot contain ] in tmux option syntax"))
          (literal-format
           (format nil "~A[~A]" name
                   (if (integerp key)
                       (write-to-string key :base 10 :radix nil)
                       key)))))
      (literal-format name)))

(defun configuration-mutation-builder (command scope scope-flags name value value-p
                                       key key-p format-p append hooks-only unset-p)
  "Build one mutation from the exact live daemon catalog selected by preflight."
  (lambda (witness current)
    (declare (ignore current))
    (let* ((catalog (configuration-catalog (server-witness-version witness)))
           (spec (catalog-option catalog name scope :hooks-only hooks-only))
           (reference (configuration-option-reference
                       catalog spec (option-spec-name spec) key key-p)))
      (when (and (not hooks-only) (option-spec-hook-p spec))
        (invalid-argument "Use SET-HOOK or UNSET-HOOK for hook option ~A" name))
      (when (and append
                 (not (or (eq (option-spec-kind spec) :string)
                          (and (option-spec-array-p spec) (not key-p)))))
        (invalid-argument
         "Option ~A does not support append for this scalar or keyed array value"
         name))
      (append (list command)
              scope-flags
              (when append '("-a"))
              (when format-p '("-F"))
              (when unset-p '("-u"))
              (list "--" reference)
              (when value-p
                (list (if hooks-only
                          (text-argument value "Hook command source")
                          (configuration-value-text spec value format-p))))))))

(defun mutate-configuration (client command name value value-p scope target key key-p
                            format-p append hooks-only unset-p options)
  "Validate local authority, then defer schema selection to the live witness."
  (let ((name (checked-option-name name)))
    (multiple-value-bind (targets flags) (configuration-scope-data scope target)
      (apply #'perform-command client targets (list command name)
             :argument-builder
             (configuration-mutation-builder command scope flags name value value-p
                                             key key-p format-p append hooks-only unset-p)
             options))))

(defun environment-mutation-builder (flags name value value-p format-p hidden mode)
  "Build one literal environment mutation; MODE is :SET, :UNSET or :REMOVE."
  (lambda (witness current)
    (declare (ignore witness current))
    (append '("set-environment") flags
            (when format-p '("-F"))
            (when hidden '("-h"))
            (ecase mode (:set nil) (:unset '("-u")) (:remove '("-r")))
            (list "--" name)
            (when value-p (list (text-argument value "Environment value"))))))

(defun mutate-environment (client name value value-p scope target format-p hidden mode options)
  "Validate a raw environment table mutation and dispatch it once."
  (let ((name (checked-environment-name name)))
    (when (and (not (eq mode :set)) (or value-p format-p hidden))
      (invalid-argument "Unset/remove environment operations do not accept value flags"))
    (multiple-value-bind (targets flags) (environment-scope-data scope target)
      (apply #'perform-command client targets (list "set-environment" name)
             :argument-builder
             (environment-mutation-builder flags name value value-p format-p hidden mode)
             options))))

(in-package #:libtmux)

(defun set-option (client name value &key scope target (key nil key-p) format-p append
                                          cancel-token timeout output-limit)
  "Set one typed tmux option and return its COMMAND-OUTCOME.
SCOPE is required and names one explicit table: :SERVER, :GLOBAL-SESSION,
:SESSION, :GLOBAL-WINDOW, :WINDOW or :PANE. Local scopes require a captured
TARGET of the matching type; global scopes reject one. NAME is resolved in the
exact live daemon catalog. Native numbers, Booleans and choices are validated
before payload dispatch. User names must match @[A-Za-z0-9_.-]+ and remain
strings. KEY addresses a registered array element. FORMAT-P treats VALUE as an
explicit tmux format; otherwise VALUE is literal and typed. APPEND is supported
for strings, keyed string-array elements and unkeyed array assignment. An
unkeyed array VALUE uses that option's native tmux list grammar; use KEY when
VALUE must remain one literal element. Use UNSET-OPTION to remove state and
SET-HOOK for registered hooks. Never retries or acquires a replacement capture.
See also: SET-HOOK, UNSET-OPTION."
  (libtmux.internal::mutate-configuration
   client "set-option" name value t scope target key key-p format-p append nil nil
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun unset-option (client name &key scope target (key nil key-p)
                                    cancel-token timeout output-limit)
  "Remove one local option or array entry and return its COMMAND-OUTCOME.
SCOPE/TARGET and KEY follow SET-OPTION. The exact live catalog validates the
name, table and array shape before payload dispatch. Tmux's native unset/default
behavior applies; inherited state is not silently materialized. See SET-OPTION
for setting and scope rules. Never retries.
See also: SET-OPTION."
  (libtmux.internal::mutate-configuration
   client "set-option" name nil nil scope target key key-p nil nil nil t
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun set-hook (client name command-source &key scope target (key nil key-p) append
                                                 cancel-token timeout output-limit)
  "Install tmux COMMAND-SOURCE for one registered hook and return an outcome.
SCOPE/TARGET follow SET-OPTION. COMMAND-SOURCE is explicit tmux command
language, not Lisp code; this function neither reads nor executes it locally.
KEY selects one hook-array entry. APPEND applies to an unkeyed hook assignment;
tmux does not append command source within a keyed hook entry. The ordinary
install path never uses set-hook -R, but tmux may still run a registered native
after-hook such as after-set-hook as a consequence of this set-hook command.
Dynamic @ event sources require a live catalog that supports them. SET-OPTION
rejects registered hooks; use UNSET-HOOK to remove this state. Never retries.
See also: SET-OPTION, UNSET-HOOK."
  (libtmux.internal::mutate-configuration
   client "set-hook" name command-source t scope target key key-p nil append t nil
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun unset-hook (client name &key scope target (key nil key-p)
                                  cancel-token timeout output-limit)
  "Remove one registered hook or hook-array entry and return its outcome.
SCOPE/TARGET and KEY follow SET-HOOK. The ordinary path never uses set-hook -R,
but tmux may run a remaining native after-hook as a consequence of this
set-hook command. The operation does not retry and validates the exact live
catalog before payload dispatch.
See also: SET-HOOK."
  (libtmux.internal::mutate-configuration
   client "set-hook" name nil nil scope target key key-p nil nil t t
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun set-environment (client name value &key scope target format-p hidden
                                           cancel-token timeout output-limit)
  "Set one raw tmux environment entry and return its COMMAND-OUTCOME.
SCOPE is required: :GLOBAL rejects TARGET; :SESSION requires a captured session.
NAME must match [A-Za-z_][A-Za-z0-9_]*. VALUE is literal unless FORMAT-P
explicitly requests tmux format expansion. HIDDEN sets tmux's hidden flag.
This mutates one raw table, not an effective merged child environment. Never
retries or refreshes captured observations. See UNSET-ENVIRONMENT for deletion
and REMOVE-ENVIRONMENT for an explicit tombstone.
See also: REMOVE-ENVIRONMENT, UNSET-ENVIRONMENT."
  (libtmux.internal::mutate-environment
   client name value t scope target format-p hidden :set
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun unset-environment (client name &key scope target cancel-token timeout output-limit)
  "Delete NAME from one raw tmux environment table and return its outcome.
SCOPE/TARGET follow SET-ENVIRONMENT. Absence remains tmux's native idempotent
unset behavior. This is distinct from REMOVE-ENVIRONMENT's tombstone; use
SET-ENVIRONMENT to store a present value.
See also: REMOVE-ENVIRONMENT, SET-ENVIRONMENT."
  (libtmux.internal::mutate-environment
   client name nil nil scope target nil nil :unset
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun remove-environment (client name &key scope target cancel-token timeout output-limit)
  "Store tmux's removal marker for NAME and return its COMMAND-OUTCOME.
SCOPE/TARGET follow SET-ENVIRONMENT. A removal marker is distinct from absence
and from a present empty string. UNSET-ENVIRONMENT deletes the entry instead.
Never retries the mutation.
See also: SET-ENVIRONMENT, UNSET-ENVIRONMENT."
  (libtmux.internal::mutate-environment
   client name nil nil scope target nil nil :remove
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))
