(in-package #:libtmux.internal)

(defclass subprocess-transport () ())

(defgeneric execute-command (transport argv &key input timeout output-limit cancel-token keep-input-open)
  (:documentation "Internal transport protocol. Return an owned command outcome."))

(defmethod execute-command ((transport subprocess-transport) argv
                            &key input (timeout 30) (output-limit (* 16 1024 1024))
                              cancel-token keep-input-open)
  (declare (ignore transport))
  (run-process argv :input input :timeout timeout :output-limit output-limit
                    :cancel-token cancel-token :keep-input-open keep-input-open))

(defun version-components (text)
  (let* ((version (string-trim '(#\Space #\Tab #\Newline #\Return) text))
         (dot (position #\. version))
         (suffix (and dot (position-if-not #'digit-char-p version :start (1+ dot)))))
    (unless (and dot (plusp dot)
                 (every #'digit-char-p (subseq version 0 dot))
                 (< (1+ dot) (or suffix (length version)))
                 (or (null suffix)
                     (and (= suffix (1- (length version)))
                          (char<= #\a (char version suffix) #\z))))
      (error 'libtmux:unsupported-tmux
             :message (format nil "Cannot identify the tmux release ~S" text)))
    (list (parse-integer version :end dot)
          (parse-integer version :start (1+ dot) :end suffix)
          (if suffix (1+ (- (char-code (char version suffix)) (char-code #\a))) 0))))

(defun supported-version (text)
  (let ((components (version-components text)))
    (unless (loop for actual in components for minimum in '(3 3 1)
                  when (> actual minimum) return t
                  when (< actual minimum) return nil
                  finally (return t))
      (error 'libtmux:unsupported-tmux
             :message (format nil "tmux 3.3a or newer is required; found ~A" text)))
    (copy-seq text)))

(defun version-at-least-p (actual minimum)
  (loop for value in (version-components actual) for bound in (version-components minimum)
        when (> value bound) return t
        when (< value bound) return nil
        finally (return t)))

(defstruct operation token owner)

(in-package #:libtmux)

(defclass client ()
  ((program :initarg :program :initform nil)
   (socket-name :initarg :socket-name :initform nil)
   (socket-path :initarg :socket-path :initform nil)
   (config-file :initarg :config-file :initform nil)
   (version :initform nil)
   (timeout :initarg :timeout :initform 30)
   (output-limit :initarg :output-limit :initform (* 16 1024 1024))
   (transport :initarg :transport
              :initform (make-instance 'libtmux.internal::subprocess-transport))
   (lock :initform (libtmux.internal::make-lock "tmux client"))
   (changed :initform (libtmux.internal::make-condition-variable))
   (state :initform :open)
   (active :initform nil)
   (cleanup-owner :initform nil)
   (cleanup-jobs :initform nil)
   (cleanup-failures :initform nil)
   (context :initform (gensym (format nil "SERVER-~36R-"
                                     (random (ash 1 128) (make-random-state t)))))
   (generation :initform 0)
   (witness :initform nil))
  (:documentation "A connection scope with one external-operation lease.
Closing cancels owned work and leaves the tmux daemon alive. Captured data may
outlive the client. Public operations never expose its mutable storage."))

(defmethod print-object ((client client) stream)
  (print-unreadable-object (client stream :type t :identity t)
    (format stream "~A" (slot-value client 'state))))

(defun client-open-p (client)
  "Return whether CLIENT's lifecycle is open; no tmux I/O.
An active operation may still cause CLIENT-BUSY when new work is attempted."
  (libtmux.internal::call-with-lock
   (slot-value client 'lock) (lambda () (eq (slot-value client 'state) :open))))

(defun client-cleanup-failures (client)
  "Return a fresh vector of secondary cleanup conditions, newest first. No I/O."
  (libtmux.internal::call-with-lock
   (slot-value client 'lock)
   (lambda () (coerce (slot-value client 'cleanup-failures) 'simple-vector))))

(defun tmux-version (client)
  "Return a fresh copy of the release string observed when CLIENT opened."
  (let ((version (slot-value client 'version)))
    (and version (copy-seq version))))

(defgeneric close-client (client)
  (:documentation "Reject new work, cancel active work and release owned resources.
The operation is idempotent and does not kill the daemon. A bounded teardown
failure signals CLEANUP-FAILED; the active owner still retains cleanup duty."))

(in-package #:libtmux.internal)

(defun record-cleanup-failure (client condition)
  ;; No user callback or printer may replace a protected nonlocal exit.
  (handler-case
      (call-with-lock
       (slot-value client 'libtmux::lock)
       (lambda ()
         (setf (slot-value client 'libtmux::cleanup-failures)
               (subseq (cons condition (slot-value client 'libtmux::cleanup-failures))
                       0 (min 16 (1+ (length (slot-value client 'libtmux::cleanup-failures))))))))
    (serious-condition () nil)))

(defun retain-cleanup-job (client job)
  (call-with-lock
   (slot-value client 'libtmux::lock)
   (lambda ()
     (pushnew job (slot-value client 'libtmux::cleanup-jobs))
     (setf (slot-value client 'libtmux::state) :closing))))

(defun call-with-client-scope (client body)
  (let ((normal nil))
    (unwind-protect
         (multiple-value-prog1 (funcall body client) (setf normal t))
      (handler-case (libtmux:close-client client)
        (error (condition)
          (if normal (error condition) (record-cleanup-failure client condition)))))))

(defun call-with-operation (client token function)
  (let ((operation (make-operation :token (or token (libtmux:make-cancellation-token))
                                   :owner (current-thread))))
    (check-type (operation-token operation) libtmux:cancellation-token)
    (let ((failure
            (call-with-lock
             (slot-value client 'libtmux::lock)
             (lambda ()
               (cond ((not (eq (slot-value client 'libtmux::state) :open)) :closed)
                     ((slot-value client 'libtmux::active) :busy)
                     (t (setf (slot-value client 'libtmux::active) operation) nil))))))
      (case failure
        (:closed (error 'libtmux:client-closed
                        :message "Client is closed; open a new client"))
        (:busy (error 'libtmux:client-busy
                      :message "Client has an active external operation"))))
    (unwind-protect
         (let ((*operation-client* client))
           (funcall function (operation-token operation)))
      (call-with-lock
       (slot-value client 'libtmux::lock)
       (lambda ()
         (setf (slot-value client 'libtmux::active) nil)
         (when (and (eq (slot-value client 'libtmux::state) :closing)
                    (not (slot-value client 'libtmux::cleanup-jobs))
                    (not (slot-value client 'libtmux::witness))
                    (not (slot-value client 'libtmux::cleanup-owner)))
           (setf (slot-value client 'libtmux::state) :closed))
         (condition-broadcast (slot-value client 'libtmux::changed)))))))

(defun client-argv (client arguments)
  (let ((name (unless *command-socket-path* (slot-value client 'libtmux::socket-name)))
        (path (or *command-socket-path* (slot-value client 'libtmux::socket-path)))
        (config (slot-value client 'libtmux::config-file)))
    (append (list (slot-value client 'libtmux::program) "-u")
            (when name (list "-L" name)) (when path (list "-S" path))
            (when config (list "-f" config)) (coerce arguments 'list))))

(defun execute-tmux (client arguments token timeout output-limit input &key keep-input-open)
  (execute-command (slot-value client 'libtmux::transport)
                   (client-argv client arguments) :input input :timeout timeout
                   :output-limit output-limit :cancel-token token :keep-input-open keep-input-open))

(in-package #:libtmux)

(defmethod close-client ((client client))
  (let ((active
          (libtmux.internal::call-with-lock
           (slot-value client 'lock)
           (lambda ()
             (unless (eq (slot-value client 'state) :closed)
               (setf (slot-value client 'state) :closing))
             (slot-value client 'active)))))
    (when active
      (cancel (libtmux.internal::operation-token active))
      (when (eq (libtmux.internal::operation-owner active)
                (libtmux.internal::current-thread))
        (error 'cleanup-failed :message "Cannot join an operation from its own thread")))
    (let* ((deadline (+ (libtmux.internal::monotonic-seconds) 0.75))
           (acquired
             (libtmux.internal::call-with-lock
              (slot-value client 'lock)
              (lambda ()
                (loop while (or (slot-value client 'active) (slot-value client 'cleanup-owner))
                      for remaining = (- deadline (libtmux.internal::monotonic-seconds))
                      do (unless (and (plusp remaining)
                                      (libtmux.internal::condition-wait
                                       (slot-value client 'changed) (slot-value client 'lock)
                                       remaining))
                           (return nil))
                      finally (return (setf (slot-value client 'cleanup-owner)
                                            (libtmux.internal::current-thread))))))))
      (unless acquired
        (error 'cleanup-failed
               :message "Active operation has not completed cleanup; client stays closing"))
      (unwind-protect
           (let ((libtmux.internal::*operation-client* client))
             (dolist (job (copy-list (slot-value client 'cleanup-jobs)))
               (when (libtmux.internal::cleanup-job job)
                 (setf (slot-value client 'cleanup-jobs)
                       (remove job (slot-value client 'cleanup-jobs)))))
             (unless (slot-value client 'cleanup-jobs)
               (libtmux.internal::release-client-witness client)))
        (libtmux.internal::call-with-lock
         (slot-value client 'lock)
         (lambda ()
           (setf (slot-value client 'cleanup-owner) nil
                 (slot-value client 'state)
                 (if (or (slot-value client 'cleanup-jobs) (slot-value client 'witness)) :closing :closed))
           (libtmux.internal::condition-broadcast (slot-value client 'changed)))))
      (when (slot-value client 'cleanup-jobs)
        (error 'cleanup-failed :resource (first (slot-value client 'cleanup-jobs))
               :message "Owned process cleanup remains incomplete; retry CLOSE-CLIENT"))))
  (values))

(defun open-client (&key (program "tmux") socket-name socket-path config-file
                        (timeout 30) (output-limit (* 16 1024 1024)))
  "Open an SBCL/Linux subprocess client and check its tmux version.
PROGRAM must resolve to a native x86_64 ELF tmux executable.
SOCKET-NAME and SOCKET-PATH are mutually exclusive; omission selects tmux's
default socket. No daemon is started. TIMEOUT is seconds; OUTPUT-LIMIT bounds
combined stdout/stderr bytes per command. Signals an operational condition on
version/launch failure. Returned configuration strings are owned by the client."
  (libtmux.internal::check-limits timeout output-limit)
  (when (and socket-name socket-path)
    (libtmux.internal::invalid-argument "Specify socket-name or socket-path, not both"))
  (dolist (value (list socket-name socket-path config-file))
    (when value
      (unless (and (stringp value) (plusp (length value)) (not (find #\Null value)))
        (libtmux.internal::invalid-argument "Socket/configuration values must be nonempty strings without NUL"))))
  (let ((client (make-instance 'client
                 :program (libtmux.internal::native-program program)
                 :socket-name (and socket-name (copy-seq socket-name))
                 :socket-path (and socket-path (libtmux.internal::absolute-native-path socket-path))
                 :config-file (and config-file (libtmux.internal::absolute-native-path config-file))
                 :timeout timeout :output-limit output-limit))
        (opened nil))
    (unwind-protect
         (handler-bind ((libtmux-error
                          (lambda (condition) (setf (slot-value condition 'client) client))))
           (let* ((outcome (run-command client '("-V") :effect :read))
                  (text (string-trim '(#\Newline #\Return)
                                      (libtmux.internal::strict-text (outcome-stdout outcome)))))
             (unless (and (>= (length text) 5) (string= "tmux " text :end2 5))
               (error 'unsupported-tmux :outcome outcome
                      :message "The selected executable did not report a tmux release"))
             (setf (slot-value client 'version)
                   (libtmux.internal::supported-version (subseq text 5))))
           (setf opened t)
           client)
      (unless opened
        (handler-case (close-client client)
          (error (condition) (libtmux.internal::record-cleanup-failure client condition)))))))

(defmacro with-client ((name &rest options) &body body)
  "Bind NAME to a client and close the original resource on every exit.
Body declarations and multiple values are preserved. Cleanup failure signals
after normal return; during unwind it is retained in CLIENT-CLEANUP-FAILURES."
  (let ((owned (gensym "CLIENT")))
    `(let ((,owned (open-client ,@options)))
       (libtmux.internal::call-with-client-scope
        ,owned (lambda (,name) ,@body)))))

(defun run-command (client arguments &key effect input cancel-token
                       (timeout (slot-value client 'timeout))
                       (output-limit (slot-value client 'output-limit)))
  "Execute explicit tmux argv and return a retained COMMAND-OUTCOME.
EFFECT must be :READ or :MUTATION. Arguments are literal argv strings; tmux's
own command/format grammar still applies. INPUT is an octet vector or NIL.
This escape hatch does not validate captured target identities. Failures signal
conditions retaining the outcome; uncertain mutations are never retried."
  (unless (member effect '(:read :mutation))
    (libtmux.internal::invalid-argument "Run-command requires :effect :read or :mutation"))
  (let ((arguments (libtmux.internal::argument-vector arguments)))
    (unless (plusp (length arguments))
      (libtmux.internal::invalid-argument "Run-command requires at least one argument"))
    (libtmux.internal::check-limits timeout output-limit)
    (handler-bind ((libtmux-error
                     (lambda (condition) (setf (slot-value condition 'client) client))))
      (libtmux.internal::call-with-operation
       client cancel-token
       (lambda (token)
         (libtmux.internal::check-outcome
          (libtmux.internal::execute-tmux client arguments token timeout output-limit input)))))))
