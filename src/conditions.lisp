(in-package #:libtmux)

(defgeneric error-message (condition)
  (:documentation "Return the failure's diagnostic string. No I/O; treat it as read-only."))
(defgeneric error-cause (condition)
  (:documentation "Return the original underlying condition, or NIL. No I/O; may be shared."))
(defgeneric error-outcome (condition)
  (:documentation "Return retained COMMAND-OUTCOME evidence, or NIL before one exists.
Inspect dispatch phase and status before deciding how to recover. No I/O."))
(defgeneric error-client (condition)
  (:documentation "Return the connection client associated with the failure, or NIL.
A partially opened client may still own cleanup work; retry CLOSE-CLIENT if
cleanup failed. Reading this slot performs no I/O."))
(defgeneric error-feature (condition)
  (:documentation "Return the unsupported capability's keyword identifier. No I/O."))
(defgeneric error-setting (condition)
  (:documentation "Return the daemon setting that violates a named command contract.
The captured diagnostic value may be shared; treat it as read-only. No I/O."))
(defgeneric error-field (condition)
  (:documentation "Return the requested field key, including an unregistered key. No I/O.
An invalid caller value is retained as supplied; it need not be a keyword."))
(defgeneric error-model (condition)
  (:documentation "Return the captured model keyword implicated in a field failure. No I/O."))
(defgeneric error-target (condition)
  (:documentation "Return the stale captured target, or NIL when unavailable. No I/O."))

(define-condition libtmux-error (error)
  ((message :initarg :message :initform "Tmux operation failed"
            :reader error-message)
   (cause :initarg :cause :initform nil :reader error-cause)
   (outcome :initarg :outcome :initform nil :reader error-outcome)
   (client :initarg :client :initform nil :reader error-client))
  (:documentation "A library failure with a message, original cause and outcome.")
  (:report (lambda (condition stream)
             (write-string (error-message condition) stream))))

(define-condition invalid-argument (libtmux-error) ()
  (:documentation "An argument violates the operation's declared contract."))
(define-condition unsupported-platform (libtmux-error)
  ((feature :initarg :feature :initform :runtime-profile :reader error-feature))
  (:documentation "The selected runtime lacks a qualified backend or required facility.
ERROR-FEATURE identifies the requirement; ERROR-CAUSE retains a failed probe
when available. OPEN-CLIENT checks the profile before resolving PROGRAM.
See also: OPEN-CLIENT, ERROR-FEATURE, ERROR-CAUSE."))
(define-condition unsupported-tmux (libtmux-error) ()
  (:documentation "The selected tmux does not meet the supported version floor."))
(define-condition unsupported-capability (libtmux-error)
  ((feature :initarg :feature :reader error-feature)
   (required-version :initarg :required-version)
   (actual-version :initarg :actual-version))
  (:documentation "The live daemon does not support the requested operation contract."))

(defun error-required-version (condition)
  "Return an owned copy of the capability's minimum tmux release."
  (copy-seq (slot-value condition 'required-version)))

(defun error-actual-version (condition)
  "Return an owned copy of the live daemon release that failed the capability check."
  (copy-seq (slot-value condition 'actual-version)))
(define-condition unsupported-configuration (libtmux-error)
  ((setting :initarg :setting :initform nil :reader error-setting)
   (commands :initarg :commands :initform nil))
  (:documentation "Daemon configuration overrides a required built-in command contract."))

(defun error-commands (condition)
  "Return an owned vector of command spellings implicated in the configuration failure."
  (map 'vector #'copy-seq (slot-value condition 'commands)))
(define-condition client-closed (libtmux-error) ()
  (:documentation "An external operation was attempted on a closing/closed client."))
(define-condition client-busy (libtmux-error) ()
  (:documentation "Another external operation already owns the client's lease."))
(define-condition cleanup-failed (libtmux-error)
  ((resource :initarg :resource :initform nil))
  (:documentation "Owned resources could not be released within the cleanup bound."))
(define-condition command-failed (libtmux-error) ()
  (:documentation "The command failed; ERROR-OUTCOME retains diagnostics."))
(define-condition outcome-unknown (command-failed) ()
  (:documentation "A dispatched operation did not establish its final outcome."))
(define-condition command-cancelled (outcome-unknown) ()
  (:documentation "Cancellation stopped an operation; inspect dispatch phase."))
(define-condition deadline-exceeded (outcome-unknown) ()
  (:documentation "The command exceeded its absolute deadline."))
(define-condition output-limit-exceeded (outcome-unknown) ()
  (:documentation "Combined stdout/stderr exceeded the configured byte limit."))
(define-condition decoding-error (libtmux-error) ()
  (:documentation "Captured bytes do not satisfy the expected text/record codec."))

(define-condition incomplete-snapshot (libtmux-error)
  ((details :initarg :details :initform nil))
  (:documentation "Captured rows contradict each other or lack required references."))
(define-condition field-unavailable (libtmux-error)
  ((field :initarg :field :reader error-field)
   (model :initarg :model :reader error-model))
  (:documentation "The field is unregistered for this model or its relation is unloaded."))
(define-condition stale-target (libtmux-error)
  ((target :initarg :target :initform nil :reader error-target))
  (:documentation "Captured target authority no longer agrees with the live server."))
