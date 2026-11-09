(defpackage #:libtmux.control
  (:use #:cl)
  (:export #:connection #:request #:connection-error #:connection-start-failed
           #:connection-cleanup-failed #:connection-closed #:connection-busy
           #:error-connection #:open-connection #:close-connection #:with-connection
           #:connection-state #:connection-failure #:connection-cleanup-failures
           #:pending-cleanups #:submit-command #:await-request #:request-state
           #:cancel-request #:next-event)
  (:documentation "Persistent native tmux commands and bounded byte events.
Load the optional LIBTMUX/CONTROL system. The qualified backend requires the
core SBCL/Linux profile and an actual tmux daemon >=3.7. Connections own a
worker and process independently of their originating LIBTMUX:CLIENT.
Submission is nonblocking; waits use condition notifications. One worker
serializes requests and reads all protocol data. No application callback
runs in that worker. Commands use tmux argv, not shell source.
Results and events own their mutable bytes and containers. A completed
command queue does not establish application readiness. No automatic replay
or reconnect occurs. See also: WITH-CONNECTION, SUBMIT-COMMAND, NEXT-EVENT."))

(in-package #:libtmux.control)

(defclass connection ()
  ((peer :initarg :peer :reader %peer)
   (cleanup-failures :initform nil))
  (:documentation "An owned persistent tmux connection with one protocol worker.
Use WITH-CONNECTION or CLOSE-CONNECTION to release it. Closing the originating
core client does not close this resource. Captured core observations remain
separate; raw control commands do not refresh them.
See also: OPEN-CONNECTION, CONNECTION-STATE, PENDING-CLEANUPS."))

(defclass request ()
  ((handle :initarg :handle :reader %handle))
  (:documentation "One queued command and its retained dispatch/result evidence.
Keep this handle to await or cancel work. A wait timeout leaves it live.
See also: SUBMIT-COMMAND, AWAIT-REQUEST, CANCEL-REQUEST."))

(defgeneric error-connection (condition)
  (:documentation "Return the retained connection implicated in a CONNECTION-ERROR. No I/O.
See also: CLOSE-CONNECTION, LIBTMUX:ERROR-CAUSE."))

(define-condition connection-error (libtmux:libtmux-error)
  ((connection :initarg :connection :reader error-connection))
  (:documentation "A control failure retaining its connection and original cause.
See also: ERROR-CONNECTION, LIBTMUX:ERROR-CAUSE."))

(define-condition connection-start-failed (connection-error libtmux:command-failed) ()
  (:documentation "Startup failed after allocating a connection resource.
ERROR-CONNECTION retains the resource even if cleanup also failed. Core
argument and unsupported-capability errors before allocation stay core types.
See also: OPEN-CONNECTION, CLOSE-CONNECTION, PENDING-CLEANUPS."))

(define-condition connection-cleanup-failed (connection-error libtmux:cleanup-failed) ()
  (:documentation "Closing failed; retry CLOSE-CONNECTION on ERROR-CONNECTION.
The resource remains discoverable through PENDING-CLEANUPS. No mutation is
replayed. See also: CONNECTION-CLEANUP-FAILURES, LIBTMUX:ERROR-CAUSE."))

(define-condition connection-closed (connection-error libtmux:client-closed) ()
  (:documentation "Submission attempted on a closing or closed connection.
See also: CONNECTION-STATE, SUBMIT-COMMAND."))

(define-condition connection-busy (connection-error libtmux:client-busy) ()
  (:documentation "The bounded request queue, including active work, is full.
Submission did not dispatch this command. See also: SUBMIT-COMMAND."))

(defun %connection-for-peer (peer)
  (libtmux.internal::with-control-lock
   peer (lambda ()
          (or (libtmux.internal::control-peer-api-object peer)
              (setf (libtmux.internal::control-peer-api-object peer)
                    (make-instance 'connection :peer peer))))))

(defun open-connection (client session &key (timeout 30) (request-limit 16)
                                          (event-limit 256) (event-byte-limit 4194304)
                                          (reply-byte-limit 1048576))
  "Attach a separate owned control connection to a captured SESSION.
CLIENT supplies the core endpoint and authority. Startup preflights the target
and requires the live daemon to be >=3.7. TIMEOUT bounds startup admission and
supervised execution; platform preparation and cleanup add caller wall time.
REQUEST-LIMIT includes active and queued work. Events drop oldest entries at
EVENT-LIMIT or EVENT-BYTE-LIMIT and report loss. REPLY-BYTE-LIMIT bounds each
request's retained output; overflow closes the connection with a cause.
This call blocks until ready or failed. All limits must be positive integers
except the nonnegative real TIMEOUT. No daemon is started or terminated.
See also: WITH-CONNECTION, CLOSE-CONNECTION, SUBMIT-COMMAND, NEXT-EVENT."
  (handler-case
      (%connection-for-peer
       (libtmux.internal::start-control-peer client session :timeout timeout
         :request-limit request-limit :event-limit event-limit
         :event-byte-limit event-byte-limit :reply-byte-limit reply-byte-limit))
    (libtmux.internal::control-start-failed (condition)
      (error 'connection-start-failed
             :connection (%connection-for-peer (libtmux.internal::failed-control-peer condition))
             :cause condition :message "Control startup failed; inspect the cause and retained connection"))))

(defun connection-state (connection)
  "Return :STARTING, :READY, :CLOSING or :CLOSED without I/O.
This is an observation, not a lease for subsequent submission.
See also: SUBMIT-COMMAND, CONNECTION-FAILURE."
  (check-type connection connection)
  (libtmux.internal::with-control-lock
   (%peer connection) (lambda () (libtmux.internal::control-peer-state (%peer connection)))))

(defun connection-failure (connection)
  "Return the retained worker failure condition, or NIL, without I/O.
Conditions retain identity; byte data comes from NEXT-EVENT or AWAIT-REQUEST.
See also: CONNECTION-STATE, CONNECTION-CLEANUP-FAILURES."
  (check-type connection connection)
  (libtmux.internal::with-control-lock
   (%peer connection) (lambda () (libtmux.internal::control-peer-failure (%peer connection)))))

(defun connection-cleanup-failures (connection)
  "Return a fresh vector of the last 16 close failures, newest first. No I/O.
Condition objects are retained by identity. WITH-CONNECTION records secondary
cleanup failures while preserving an existing body error or nonlocal exit.
See also: CLOSE-CONNECTION, PENDING-CLEANUPS."
  (check-type connection connection)
  (libtmux.internal::with-control-lock
   (%peer connection) (lambda () (coerce (slot-value connection 'cleanup-failures) 'vector))))

(defun pending-cleanups ()
  "Return a fresh vector of connections retaining failed cleanup work. No I/O.
Retry CLOSE-CONNECTION explicitly. Successful close removes the entry.
See also: CONNECTION-CLEANUP-FAILED, ERROR-CONNECTION."
  (let ((peers (libtmux.internal::call-with-lock
                libtmux.internal::*pending-control-lock*
                (lambda () (copy-list libtmux.internal::*pending-control-peers*)))))
    (map 'vector #'%connection-for-peer peers)))

(defun %record-cleanup-failure (connection condition)
  (handler-case
      (libtmux.internal::with-control-lock
       (%peer connection)
       (lambda ()
         (unless (eq condition (first (slot-value connection 'cleanup-failures)))
           (setf (slot-value connection 'cleanup-failures)
                 (subseq (cons condition (slot-value connection 'cleanup-failures))
                         0 (min 16 (1+ (length (slot-value connection 'cleanup-failures)))))))))
    (serious-condition () nil)))

(defgeneric close-connection (connection)
  (:documentation "Close this connection's worker and process; return NIL after cleanup.
Leave the tmux daemon running. Concurrent closes serialize; repeated successful
close is harmless. In-flight results retain partial output and dispatch state.
Cleanup can add time beyond request deadlines. Failure signals
CONNECTION-CLEANUP-FAILED and retains this resource for explicit retry.
See also: WITH-CONNECTION, PENDING-CLEANUPS, CONNECTION-CLEANUP-FAILURES."))

(defmethod close-connection ((connection connection))
  (handler-case (libtmux.internal::close-control-peer (%peer connection))
    (error (cause)
      (let ((condition (make-condition 'connection-cleanup-failed
                        :connection connection :resource connection :cause cause
                        :message "Control cleanup failed; retry closing the retained connection")))
        (%record-cleanup-failure connection condition)
        (error condition)))))

(defun %call-with-connection-scope (connection body)
  (let ((completed nil))
    (unwind-protect
         (multiple-value-prog1 (funcall body connection) (setf completed t))
      (handler-case (close-connection connection)
        (error (condition)
          (%record-cleanup-failure connection condition)
          (when completed (error condition)))))))

(defmacro with-connection ((name client session &rest options) &body body)
  "Bind NAME to a control connection and close the original resource on exit.
Evaluate CLIENT, SESSION and OPEN-CONNECTION options once. BODY accepts
declarations and returns all its values. Rebinding NAME cannot redirect cleanup.
After normal return, propagate cleanup failure; during an error or nonlocal
exit, preserve that exit and record cleanup failure on the connection.
See also: OPEN-CONNECTION, CLOSE-CONNECTION, CONNECTION-CLEANUP-FAILURES."
  (let ((resource (gensym "CONNECTION")))
    `(let ((,resource (open-connection ,client ,session ,@options)))
       (%call-with-connection-scope ,resource (lambda (,name) ,@body)))))

(defun submit-command (connection argv &key effect (timeout 30))
  "Queue copied tmux ARGV and return a REQUEST without waiting for its reply.
EFFECT must explicitly be :READ or :MUTATION; it records caller intent, not a
command restriction. TIMEOUT is a nonnegative real deadline budget starting at
submission, including queue time. A zero budget can expire before dispatch.
Commands execute serially. Full queues signal CONNECTION-BUSY; closing ones
signal CONNECTION-CLOSED. Use argv for tmux syntax, not shell interpolation.
This raw path does not validate or refresh captured operational targets.
See also: AWAIT-REQUEST, CANCEL-REQUEST, REQUEST-STATE."
  (check-type connection connection)
  (handler-case
      (make-instance 'request :handle
        (libtmux.internal::submit-control-command (%peer connection) argv :effect effect :timeout timeout))
    (libtmux:client-busy (cause)
      (error 'connection-busy :connection connection :cause cause :message "Control request queue is full"))
    (libtmux:client-closed (cause)
      (error 'connection-closed :connection connection :cause cause :message "Control connection is closed"))))

(defun request-state (request)
  "Return retained request state without I/O.
States are :QUEUED, :WRITING, :RUNNING, :COMPLETED, :FAILED, :TIMED-OUT,
:CANCELLED and :CLOSED. A terminal result is never replaced by cancellation.
See also: AWAIT-REQUEST, CANCEL-REQUEST."
  (check-type request request)
  (let ((handle (%handle request)))
    (libtmux.internal::with-control-lock
     (libtmux.internal::control-request-peer handle)
     (lambda () (libtmux.internal::control-request-state handle)))))

(defun await-request (request &key (timeout 30))
  "Wait for owned result/:READY, or return NIL/:TIMEOUT without cancelling.
TIMEOUT is nonnegative real seconds or NIL for an unbounded wait. Zero polls.
The result plist contains :STATUS, :OUTPUT bytes, :WIRE-TAIL bytes,
:TRUNCATED-P, :EFFECT, :DISPATCHED-P, :REASON and :REPLY-COUNT. Wire tail is
unterminated protocol data, not decoded output. Positive stdin progress makes
DISPATCHED-P true conservatively, even for an incomplete line. A dispatched
failed/cancelled/timed-out/closed request may have effects; never infer rollback.
COMPLETED means the command queue reached its marker, not application readiness.
Only framed replies enter OUTPUT; unframed lines remain notification events.
Repeated awaits return fresh byte storage. No exception hides a terminal result.
See also: SUBMIT-COMMAND, CANCEL-REQUEST, NEXT-EVENT."
  (check-type request request)
  (libtmux.internal::await-control-request (%handle request) :timeout timeout))

(defun cancel-request (request)
  "Request cancellation; return true only when this call changes live work.
Queued work is removed without dispatch or connection closure. Active work
closes its connection and retires unissued queued requests. The worker records
write progress before publishing :CANCELLED; await it to inspect that evidence.
Cancellation winning before completion preserves :CANCELLED; an already terminal
request is unchanged. No command is replayed and dispatched effects are not undone.
See also: AWAIT-REQUEST, REQUEST-STATE, CLOSE-CONNECTION."
  (check-type request request)
  (libtmux.internal::cancel-control-request (%handle request)))

(defun next-event (connection &key (timeout 30))
  "Wait for an owned event/:READY or NIL/:TIMEOUT on this connection.
TIMEOUT is nonnegative real seconds or NIL; zero polls. :OUTPUT has :PANE,
:AGE, :EXTENDED-P and :DATA octets, preserving invalid UTF-8. :NOTIFICATION
contains a raw line in :DATA; unsolicited :REPLY also has :FAILED-P.
:GAP reports :EVENTS and :BYTES dropped from the bounded queue. An oversized
new event reports loss without discarding retained smaller events.
:END follows retained events, with :REASON, :EXIT-CODE, :DIAGNOSTICS bytes,
:WIRE-TAIL bytes and :CAUSE. After end, repeated reads return end immediately.
Causes retain condition identity. No application callback executes in the reader.
See also: OPEN-CONNECTION, AWAIT-REQUEST, CONNECTION-FAILURE."
  (check-type connection connection)
  (libtmux.internal::next-control-event (%peer connection) :timeout timeout))

(defmethod print-object ((object connection) stream)
  (print-unreadable-object (object stream :type t :identity t)
    (write (connection-state object) :stream stream)))

(defmethod print-object ((object request) stream)
  (print-unreadable-object (object stream :type t :identity t)
    (write (request-state object) :stream stream)))
