(in-package #:libtmux)

(defgeneric outcome-status (outcome)
  (:documentation "Return :SUCCEEDED, :FAILED, :UNKNOWN or :NOT-DISPATCHED. No I/O.
These describe retained evidence, not rollback. Observation failure is separate
from mutation success; inspect OUTCOME-OBSERVATION-ERROR and OUTCOME-VALUE."))
(defgeneric outcome-phase (outcome)
  (:documentation "Return retained dispatch evidence, without I/O.
Raw process phases are :PREPARED, :LAUNCHING, :DISPATCHED and :EXITED. Named
operations may also report :PREFLIGHT or :GUARD-REJECTED before payload dispatch.
Explicit server termination reports :SERVER-TERMINATED only after retained
pidfd readiness proves exit. Phase is separate from OUTCOME-STATUS; an exited
queue can have partially completed effects even when it reported failure."))
(defgeneric outcome-exit-code (outcome)
  (:documentation "Return the subprocess's integer exit status, or NIL if unknown. No I/O."))
(defgeneric outcome-reason (outcome)
  (:documentation "Return the retained failure reason keyword, or NIL. No I/O.
Examples include :DEADLINE and :CANCELLED; inspect the condition and phase too."))
(defgeneric outcome-elapsed (outcome)
  (:documentation "Return elapsed monotonic seconds for this retained result. No I/O.
Raw RUN-COMMAND measures its subprocess operation. Named operations include
preflight, dispatch and follow-up acquisition in their retained outcome timing."))
(defgeneric outcome-observation-error (outcome)
  (:documentation "Return the condition from follow-up acquisition, or NIL. No I/O.
A successful mutation remains :SUCCEEDED when its replacement observation
fails. Do not repeat the mutation merely to obtain a replacement observation."))

(defclass command-outcome ()
  ((status :initarg :status :reader outcome-status)
   (phase :initarg :phase :reader outcome-phase)
   (arguments :initarg :arguments)
   (stdout :initarg :stdout)
   (stderr :initarg :stderr)
   (exit-code :initarg :exit-code :initform nil :reader outcome-exit-code)
   (reason :initarg :reason :initform nil :reader outcome-reason)
   (elapsed :initarg :elapsed :reader outcome-elapsed)
   (value :initarg :value :initform nil)
   (present-p :initarg :present-p :initform nil)
   (cleanup-failures :initarg :cleanup-failures :initform nil)
   (observation-error :initarg :observation-error :initform nil
                      :reader outcome-observation-error))
  (:documentation "A retained command result; byte and argument readers copy storage.
STATUS is :SUCCEEDED, :FAILED, :UNKNOWN or :NOT-DISPATCHED. PHASE is separate
dispatch evidence. An observation error does not erase a successful mutation."))

(defun outcome-arguments (outcome)
  "Return an owned vector of the effective argv strings. No external I/O."
  (map 'vector #'copy-seq (slot-value outcome 'arguments)))

(defun outcome-stdout (outcome)
  "Return a fresh octet vector containing retained standard output."
  (copy-seq (slot-value outcome 'stdout)))

(defun outcome-stderr (outcome)
  "Return a fresh octet vector containing retained diagnostic output."
  (copy-seq (slot-value outcome 'stderr)))

(defun outcome-value (outcome)
  "Return the resulting value and presence as two values, without I/O.
Copy data containers and strings; captured entity observations may be shared."
  (values (libtmux.internal::owned-data (slot-value outcome 'value))
          (slot-value outcome 'present-p)))

(defun outcome-cleanup-failures (outcome)
  "Return a fresh vector of conditions encountered while releasing the process."
  (coerce (slot-value outcome 'cleanup-failures) 'simple-vector))

(defclass cancellation-token ()
  ((lock :initform (libtmux.internal::make-lock "cancellation token"))
   (cancelled-p :initform nil)
   (registrations :initform nil))
  (:documentation "One-way cancellation state; idle tokens own no OS descriptors."))

(defun make-cancellation-token ()
  "Create a token for one or more operations. CANCEL is idempotent."
  (make-instance 'cancellation-token))

(defun cancelled-p (token)
  "Return whether TOKEN has been cancelled, without external I/O."
  (libtmux.internal::call-with-lock
   (slot-value token 'lock)
   (lambda () (slot-value token 'cancelled-p))))

(defun cancel (token)
  "Cancel registered operations and return true only for the first request.
Cancellation wakes each active owner. It does not wait for completion or undo
a mutation. Inspect the operation's outcome and dispatch phase."
  (check-type token cancellation-token)
  (libtmux.internal::call-with-lock
   (slot-value token 'lock)
   (lambda ()
     (unless (slot-value token 'cancelled-p)
       (setf (slot-value token 'cancelled-p) t)
       (dolist (fd (slot-value token 'registrations))
         (libtmux.internal::wake-operation fd))
       t))))

(in-package #:libtmux.internal)

(defun monotonic-seconds ()
  (/ (get-internal-real-time) internal-time-units-per-second))

(defun invalid-argument (format-control &rest arguments)
  (error 'libtmux:invalid-argument
         :message (apply #'format nil format-control arguments)))

(defun finite-vector (value &optional (name "Sequence"))
  (cond
    ((and (vectorp value) (not (stringp value)))
     (map 'vector #'identity value))
    ((listp value)
     (let ((length (handler-case (list-length value) (type-error () nil))))
       (unless length (invalid-argument "~A must be a finite proper list" name))
       (coerce value 'simple-vector)))
    (t (invalid-argument "~A must be a list or vector" name))))

(defun argument-vector (arguments)
  (let ((result (finite-vector arguments "Arguments")))
    (map-into result
              (lambda (argument)
                (unless (and (stringp argument)
                             (not (find #\Null argument)))
                  (invalid-argument "Arguments must be strings without NUL"))
                (copy-seq argument))
              result)
    result))

(defun octet-vector (input)
  (unless (or (null input)
              (and (vectorp input) (not (stringp input))
                   (every (lambda (byte) (typep byte '(unsigned-byte 8))) input)))
    (invalid-argument "Input must be an octet vector or NIL"))
  (map '(simple-array (unsigned-byte 8) (*)) #'identity input))

(defun check-limits (timeout output-limit)
  (unless (handler-case
              (and (realp timeout) (<= 0 timeout most-positive-double-float))
            (arithmetic-error () nil))
    (invalid-argument "Timeout must be a nonnegative finite real"))
  (unless (typep output-limit '(integer 1))
    (invalid-argument "Output limit must be a positive integer")))

(defun make-outcome (arguments status phase start &key stdout stderr code reason)
  (make-instance 'libtmux:command-outcome
                 :arguments arguments :status status :phase phase
                 :stdout (or stdout (octet-vector nil))
                 :stderr (or stderr (octet-vector nil))
                 :exit-code code :reason reason
                 :elapsed (- (monotonic-seconds) start)))

(defun check-outcome (outcome)
  (unless (eq (libtmux:outcome-status outcome) :succeeded)
    (error (case (libtmux:outcome-reason outcome)
             (:cancelled 'libtmux:command-cancelled)
             (:deadline 'libtmux:deadline-exceeded)
             (:output-limit 'libtmux:output-limit-exceeded)
             (otherwise (if (eq (libtmux:outcome-status outcome) :unknown)
                            'libtmux:outcome-unknown 'libtmux:command-failed)))
           :outcome outcome
           :message (format nil "Command ~A (~A, ~A); inspect ERROR-OUTCOME"
                            (libtmux:outcome-status outcome)
                            (libtmux:outcome-phase outcome)
                            (or (libtmux:outcome-reason outcome)
                                (libtmux:outcome-exit-code outcome)))))
  outcome)

(defun strict-text (octets)
  (handler-case (decode-utf8 octets)
    (error (cause)
      (error 'libtmux:decoding-error :cause cause
             :message "Tmux output is not valid UTF-8; use the byte API"))))

(defun register-token (token fd)
  (call-with-lock
   (slot-value token 'libtmux::lock)
   (lambda ()
     (unless (slot-value token 'libtmux::cancelled-p)
       (push fd (slot-value token 'libtmux::registrations))
       t))))

(defun retire-token (token fd)
  (call-with-lock
   (slot-value token 'libtmux::lock)
   (lambda ()
     (setf (slot-value token 'libtmux::registrations)
           (delete fd (slot-value token 'libtmux::registrations)))
     (close-descriptor fd))))

(defvar *process-started-hook* nil
  "Internal test observation point, called inside owned-process cleanup scope.")

(defvar *process-launched-hook* nil
  "Internal failure-injection point before acquiring child authority.")

(defvar *before-dispatch-hook* nil
  "Internal race-injection point after unlinking the launcher names.")

(defvar *operation-client* nil)
(defvar *command-socket-path* nil)
