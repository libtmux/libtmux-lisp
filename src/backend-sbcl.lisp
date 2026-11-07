(in-package #:libtmux.internal)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defun make-lock (name) (sb-thread:make-mutex :name name))
(defun call-with-lock (lock function)
  (sb-thread:with-mutex (lock) (funcall function)))
(defun make-condition-variable () (sb-thread:make-waitqueue))
(defun condition-broadcast (variable) (sb-thread:condition-broadcast variable))
(defun condition-wait (variable lock timeout)
  (let ((notified (sb-thread:condition-wait variable lock :timeout timeout)))
    (unless notified (sb-thread:grab-mutex lock))
    notified))
(defun current-thread () sb-thread:*current-thread*)

(defun decode-utf8 (octets)
  (sb-ext:octets-to-string octets :external-format :utf-8))
(defun encode-utf8 (text)
  (sb-ext:string-to-octets text :external-format :utf-8))

(defun absolute-native-path (text)
  (sb-ext:native-namestring
   (merge-pathnames (sb-ext:parse-native-namestring text) (uiop:getcwd))))

(defun canonical-native-path (text)
  (sb-ext:native-namestring (truename (sb-ext:parse-native-namestring text))))

(sb-alien:define-alien-routine ("pidfd_open" pidfd-open) sb-alien:int
  (pid sb-alien:int) (flags sb-alien:unsigned-int))
(sb-alien:define-alien-routine ("pidfd_send_signal" pidfd-signal) sb-alien:int
  (fd sb-alien:int) (signal sb-alien:int)
  (info sb-alien:system-area-pointer) (flags sb-alien:unsigned-int))
(sb-alien:define-alien-routine ("eventfd" eventfd-open) sb-alien:int
  (initial sb-alien:unsigned-int) (flags sb-alien:int))

(defun close-descriptor (fd) (sb-posix:close fd))

(defun wake-operation (fd)
  (sb-alien:with-alien ((one sb-alien:unsigned-long-long 1))
    (handler-case
        (sb-posix:write fd (sb-alien:alien-sap (sb-alien:addr one)) 8)
      (sb-posix:syscall-error (condition)
        (unless (= (sb-posix:syscall-errno condition) sb-posix:eagain)
          (error condition))))))

(defun nonblocking (fd)
  (sb-posix:fcntl fd sb-posix:f-setfl
                 (logior (sb-posix:fcntl fd sb-posix:f-getfl)
                         sb-posix:o-nonblock)))

(defun resolve-program (program)
  (unless (and (stringp program) (plusp (length program))
               (not (find #\Null program)))
    (invalid-argument "Program must be a nonempty string without NUL"))
  (let ((candidates
          (if (find #\/ program) (list program)
              (mapcar (lambda (directory)
                        (concatenate 'string (if (equal directory "") "." directory)
                                     "/" program))
                      (uiop:split-string (or (uiop:getenv "PATH") "")
                                         :separator '(#\:))))))
    (or (loop for candidate in candidates
              for path = (ignore-errors (truename candidate))
              when (and path
                        (ignore-errors
                          (and (sb-posix:s-isreg (sb-posix:stat-mode
                                                (sb-posix:stat path)))
                               (zerop (sb-posix:access path sb-posix:x-ok)))))
                return (namestring path))
        (invalid-argument "No executable regular file found for ~S" program))))

(defun native-program (program)
  (let ((path (resolve-program program))
        (header (make-array 20 :element-type '(unsigned-byte 8))))
    (with-open-file (stream path :element-type '(unsigned-byte 8))
      (unless (and (= 20 (read-sequence header stream))
                   (equalp (subseq header 0 6) #(127 69 76 70 2 1))
                   (= (aref header 18) 62) (zerop (aref header 19)))
        (invalid-argument "Program must be a native x86_64 ELF executable")))
    path))

(defun process-environment ()
  (append '("LC_ALL=C.UTF-8" "SHLVL=0")
          (remove-if
         (lambda (entry)
           (some (lambda (prefix)
                   (and (<= (length prefix) (length entry))
                        (string= prefix entry :end2 (length prefix))))
                 '("TMUX=" "TMUX_PANE=" "LC_ALL=" "SHLVL="
                   "BASH_COMPAT=" "BASH_XTRACEFD=")))
         (sb-ext:posix-environ))))

(sb-alien:define-alien-type poll-entry
  (sb-alien:struct poll-entry
    (fd sb-alien:int) (events sb-alien:short) (returned sb-alien:short)))
(sb-alien:define-alien-routine ("poll" descriptor-poll) sb-alien:int
  (entries (* poll-entry)) (count sb-alien:unsigned-long) (milliseconds sb-alien:int))

(defun poll-owned (entries seconds)
  "Wait only on the supplied descriptors; never dispatch application FD handlers."
  (assert (<= (length entries) 6))
  (sb-alien:with-alien ((native (array poll-entry 6)))
    (loop for (tag fd direction) in entries for i from 0
          do (setf (sb-alien:slot (sb-alien:deref native i) 'fd) fd
                   (sb-alien:slot (sb-alien:deref native i) 'events)
                   (ecase direction (:input 1) (:output 4))
                   (sb-alien:slot (sb-alien:deref native i) 'returned) 0))
    (let ((count (descriptor-poll
                  (sb-alien:cast native (* poll-entry)) (length entries)
                  (max 0 (ceiling (* (min seconds (/ 2147483647 1000)) 1000))))))
      (when (minusp count)
        (unless (= (sb-alien:get-errno) sb-posix:eintr)
          (error 'libtmux:command-failed :message "Descriptor poll failed")))
      (loop for entry in entries for i from 0
            unless (zerop (sb-alien:slot (sb-alien:deref native i) 'returned))
              collect (first entry)))))

(defvar *process-platform-ready* nil)

(defun ensure-process-platform ()
  (unless *process-platform-ready*
    (let ((fd (pidfd-open (sb-posix:getpid) 0)))
      (when (minusp fd)
        (error 'libtmux:unsupported-platform :message "Linux pidfds are required"))
      (unwind-protect
           ;; A caller outside a group-leader process gets ESRCH for its own PID.
           ;; Unsupported scope flags are rejected with EINVAL before lookup.
           (unless (or (zerop (pidfd-signal fd 0 (sb-sys:int-sap 0) 4))
                       (= (sb-alien:get-errno) sb-posix:esrch))
             (error 'libtmux:unsupported-platform
                    :message "Linux pidfd process-group signalling (kernel 6.9+) is required"))
        (sb-posix:close fd)))
    (native-program "/bin/bash")
    (setf *process-platform-ready* t)))
