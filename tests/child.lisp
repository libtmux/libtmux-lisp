;;; Deterministic child programs for the integration tests: readiness and
;;; signals, no polling sleeps. Start one with a native SBCL runtime:
;;;
;;;   RUNTIME --core CORE --script tests/child.lisp MODE ARGUMENT...
;;;
;;; It uses only SBCL itself, so it starts fast and with an empty environment.

(setf sb-alien::*default-c-string-external-format* :utf-8)
(sb-sys:enable-interrupt sb-unix:sigterm :default)
(sb-sys:enable-interrupt sb-unix:sigpipe :ignore)

(defun octets (string)
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun join-with-nul (strings)
  (let ((result (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (loop for string in strings for first = t then nil
          do (unless first (vector-push-extend 0 result))
             (loop for octet across (octets string) do (vector-push-extend octet result)))
    (coerce result '(simple-array (unsigned-byte 8) (*)))))

(defun write-all (descriptor octets)
  (let ((octets (coerce octets '(simple-array (unsigned-byte 8) (*)))) (offset 0))
    (loop while (< offset (length octets))
          do (multiple-value-bind (count errno)
                 (sb-unix:unix-write descriptor octets offset (- (length octets) offset))
               (cond ((and count (plusp count)) (incf offset count))
                     ((eql errno sb-unix:eintr))
                     (t (error "write to descriptor ~D failed: errno ~A" descriptor errno)))))))

(defun read-some (descriptor limit)
  "Read up to LIMIT octets; return an empty vector at end of input."
  (let ((buffer (make-array limit :element-type '(unsigned-byte 8))))
    (loop
      (multiple-value-bind (count errno)
          (sb-sys:with-pinned-objects (buffer)
            (sb-unix:unix-read descriptor (sb-sys:vector-sap buffer) limit))
        (cond (count (return (subseq buffer 0 count)))
              ((eql errno sb-unix:eintr))
              (t (error "read from descriptor ~D failed: errno ~A" descriptor errno)))))))

(defun read-exactly (descriptor count)
  (let ((result (make-array count :element-type '(unsigned-byte 8))) (filled 0))
    (loop while (< filled count)
          do (let ((chunk (read-some descriptor (- count filled))))
               (when (zerop (length chunk)) (error "Premature input EOF"))
               (replace result chunk :start1 filled)
               (incf filled (length chunk))))
    result))

(defun read-line-octets ()
  (loop for chunk = (read-some 0 1) until (or (zerop (length chunk)) (= 10 (aref chunk 0)))))

(defun block-forever ()
  (multiple-value-bind (reader writer) (sb-unix:unix-pipe)
    (declare (ignore writer))
    (read-some reader 1)))

(defun fork-process ()
  (sb-alien:alien-funcall (sb-alien:extern-alien "fork" (function sb-alien:int))))

(defun leave (code)
  (sb-ext:exit :code code :abort t))

(sb-alien:define-alien-type nil
  (sb-alien:struct poll-entry
    (descriptor sb-alien:int) (events sb-alien:short) (returned sb-alien:short)))

(defun descriptor-ready-p (descriptor)
  "True when a read on DESCRIPTOR would not block, including end of input."
  (sb-alien:with-alien ((entry (sb-alien:struct poll-entry)))
    (setf (sb-alien:slot entry 'descriptor) descriptor
          (sb-alien:slot entry 'events) 1
          (sb-alien:slot entry 'returned) 0)
    (plusp (sb-alien:alien-funcall
            (sb-alien:extern-alien "poll" (function sb-alien:int (* (sb-alien:struct poll-entry))
                                                    sb-alien:unsigned-long sb-alien:int))
            (sb-alien:addr entry) 1 0))))

(defun signal-channel (program socket channel)
  "Signal tmux wait channel CHANNEL on SOCKET and require success."
  (let ((process (sb-ext:run-program program (list "-N" "-S" socket "wait-for" "-S" channel)
                                     :search t :input nil :output nil :error nil)))
    (unless (eql 0 (sb-ext:process-exit-code process))
      (error "wait-for -S ~A failed" channel))))

(defun make-raw ()
  "Put standard input's terminal in raw mode with cfmakeraw, after draining output and discarding unread input."
  (sb-alien:with-alien ((termios (array (sb-alien:unsigned 8) 128)))
    (let ((pointer (sb-alien:alien-sap termios)))
      (unless (zerop (sb-alien:alien-funcall
                      (sb-alien:extern-alien "tcgetattr" (function sb-alien:int sb-alien:int
                                                                   sb-sys:system-area-pointer))
                      0 pointer))
        (error "tcgetattr failed"))
      (sb-alien:alien-funcall
       (sb-alien:extern-alien "cfmakeraw" (function sb-alien:void sb-sys:system-area-pointer))
       pointer)
      (unless (zerop (sb-alien:alien-funcall
                      (sb-alien:extern-alien "tcsetattr" (function sb-alien:int sb-alien:int
                                                                   sb-alien:int
                                                                   sb-sys:system-area-pointer))
                      0 2 pointer))
        (error "tcsetattr failed")))))

(defun exec-with-invalid-byte (arguments)
  "Replace this process with ARGUMENTS plus one final argument, the single byte 255."
  (let* ((count (1+ (length arguments)))
         (argv (sb-alien:make-alien (* (sb-alien:signed 8)) (1+ count)))
         (byte (sb-alien:make-alien (sb-alien:signed 8) 2)))
    (loop for argument in arguments for index from 0
          do (setf (sb-alien:deref argv index)
                   (sb-alien:cast (sb-alien:make-alien-string argument :external-format :utf-8)
                                  (* (sb-alien:signed 8)))))
    (setf (sb-alien:deref byte 0) -1 (sb-alien:deref byte 1) 0
          (sb-alien:deref argv (1- count)) byte
          (sb-alien:deref argv count) nil)
    (sb-alien:alien-funcall
     (sb-alien:extern-alien "execvp" (function sb-alien:int sb-alien:c-string (* (* (sb-alien:signed 8)))))
     (first arguments) argv)
    (error "execvp failed")))

(defun write-file-octets (path octets)
  (with-open-file (stream (sb-ext:parse-native-namestring path) :direction :output :if-exists :overwrite
                               :if-does-not-exist :create
                               :element-type '(unsigned-byte 8))
    (write-sequence octets stream)))

(let* ((arguments (rest sb-ext:*posix-argv*))
       (mode (first arguments))
       (rest (rest arguments)))
  (flet ((environment (name) (or (sb-ext:posix-getenv name) "<absent>")))
    (cond
      ;; Process fixtures
      ((string= mode "duplex-input")
       (write-all 1 (coerce (loop repeat 512 append (loop for i below 256 collect i)) 'vector))
       (write-all 2 (coerce (loop repeat 512 append (loop for i from 255 downto 0 collect i)) 'vector))
       (loop for chunk = (read-some 0 65536)
             until (zerop (length chunk))
             do (write-all 1 chunk)))
      ((string= mode "bytes")
       (write-all 1 (coerce (loop for i below 256 collect i) 'vector)))
      ((string= mode "argv")
       (write-all 1 (join-with-nul rest)))
      ((string= mode "context")
       (write-all 1 (join-with-nul (append (mapcar #'environment rest)
                                           (list (sb-unix:posix-getcwd))))))
      ((string= mode "held-input")
       (let* ((expected (if rest (parse-integer (first rest)) 0))
              (data (read-exactly 0 expected)))
         (when (descriptor-ready-p 0)
           (error "Input retired before the child's natural completion"))
         (write-all 1 (concatenate '(vector (unsigned-byte 8)) (octets "held:") data))))
      ((string= mode "failed")
       (write-all 1 (octets "partial"))
       (write-all 2 (octets "failed"))
       (leave 7))
      ((string= mode "exit")
       (leave (parse-integer (first rest))))
      ((string= mode "limit")
       (let ((chunk (make-array 65536 :element-type '(unsigned-byte 8) :initial-element 120)))
         (loop (write-all 1 chunk))))
      ((string= mode "exact-limit")
       (write-all 1 (make-array 4096 :element-type '(unsigned-byte 8) :initial-element 120)))
      ((string= mode "epipe")
       (sb-unix:unix-close 0)
       (write-all 2 (octets "stdin closed"))
       (block-forever))
      ((string= mode "ignore-term")
       (sb-sys:enable-interrupt sb-unix:sigterm :ignore)
       (write-file-octets (first rest) (octets "ready"))
       (block-forever))
      ((string= mode "inherited-pipes")
       (when (plusp (fork-process)) (leave 0))
       (sb-sys:enable-interrupt sb-unix:sigterm :ignore)
       (write-all 2 (octets "inherited"))
       (block-forever))
      ((string= mode "closed-pipes")
       (multiple-value-bind (reader writer) (sb-unix:unix-pipe)
         (when (plusp (fork-process))
           (sb-unix:unix-close writer)
           (read-some reader 1)
           (leave 0))
         (sb-unix:unix-close reader)
         (sb-sys:enable-interrupt sb-unix:sigterm :ignore)
         (dolist (descriptor '(0 1 2)) (sb-unix:unix-close descriptor))
         (write-all writer (octets "ready"))
         (block-forever)))
      ((string= mode "wait")
       (block-forever))
      ((string= mode "ready-done")
       (write-all 1 (octets (format nil "ready~%")))
       (read-line-octets)
       (write-all 1 (octets (format nil "done~%"))))
      ;; Pane programs: they signal tmux wait channels through the daemon's socket.
      ((string= mode "raw-write")
       (destructuring-bind (program socket channel payload) rest
         (make-raw)
         (signal-channel program socket channel)
         (read-some 0 1)
         (write-all 1 (octets payload))
         (read-some 0 1)))
      ((string= mode "pipe-reader")
       (destructuring-bind (path program socket ready consumed count suffix) rest
         (signal-channel program socket ready)
         (let ((data (read-exactly 0 (parse-integer count))))
           (write-file-octets path (concatenate '(vector (unsigned-byte 8)) data (octets suffix))))
         (signal-channel program socket consumed)))
      ((string= mode "raw-read")
       (destructuring-bind (path program socket ready consumed count) rest
         (make-raw)
         (signal-channel program socket ready)
         (write-file-octets path (read-exactly 0 (parse-integer count)))
         (signal-channel program socket consumed)
         (read-some 0 1)))
      ((string= mode "exec-with-byte")
       (exec-with-invalid-byte rest))
      ((string= mode "echo-until-eof")
       (destructuring-bind (program socket channel) rest
         (flet ((echo ()
                  (loop for chunk = (read-some 0 4096)
                        until (zerop (length chunk))
                        do (write-all 1 chunk))))
           (echo)
           (signal-channel program socket channel)
           (echo))))
      ((string= mode "record-environment")
       (destructuring-bind (name path program socket channel) rest
         (write-file-octets path (octets (or (sb-ext:posix-getenv name) "")))
         (signal-channel program socket channel)))
      ((string= mode "lock-holder")
       (destructuring-bind (ready-path release-path) rest
         (let ((release (sb-unix:unix-open release-path sb-unix:o_rdwr 0)))
           (write-file-octets ready-path (octets (format nil "~D~%" (sb-unix:unix-getpid))))
           (when (sb-sys:wait-until-fd-usable release :input 0.75)
             (read-some release 1)))))
      ((string= mode "creation")
       (write-file-octets (sb-ext:posix-getenv "LIBTMUX_RESULT")
                          (join-with-nul (list* (sb-unix:posix-getcwd)
                                                (sb-ext:posix-getenv "LIBTMUX_VALUE")
                                                rest)))
       (signal-channel (sb-ext:posix-getenv "LIBTMUX_PROGRAM")
                       (sb-ext:posix-getenv "LIBTMUX_SOCKET") "creation-ready")
       (read-some 0 1))
      ((string= mode "record")
       (destructuring-bind (name value) rest
         (write-file-octets (concatenate 'string (sb-ext:posix-getenv "WS_DIRECTORY") name)
                            (octets (format nil "~A~%~A" (sb-ext:posix-getenv "WS_VALUE") value)))
         (signal-channel (sb-ext:posix-getenv "WS_PROGRAM") (sb-ext:posix-getenv "WS_SOCKET")
                         (concatenate 'string "workspace-" name))
         (loop until (zerop (length (read-some 0 4096))))))
      (t (error "Unknown child mode ~S" mode)))))
