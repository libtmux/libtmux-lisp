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
outlive the client. Public operations never expose its mutable storage.

A client reaches one tmux server through a tmux program and an optional socket
name or path. The operations below take it as their first argument and run one
at a time per client.

#### What is on here

Operations on a tmux server take a client first. They fall into these groups:

**Connecting and closing.** `libtmux:open-client` checks the tmux version and
returns a client for the default socket or the one you name; it starts no
daemon. `libtmux:with-client` closes the client on every exit, and
`libtmux:close-client` does it by hand, cancelling active work and leaving the
daemon running. `libtmux:tmux-version`, `libtmux:client-open-p` and
`libtmux:client-cleanup-failures` report the release seen at open and the
lifecycle, without contacting tmux. `libtmux.control:open-connection` takes a
client and a captured session and attaches a separate control connection,
which needs a daemon at tmux 3.8 or newer.

`libtmux:open-client`, `libtmux:with-client`, `libtmux:close-client`,
`libtmux:tmux-version`, `libtmux:client-open-p`,
`libtmux:client-cleanup-failures` and `libtmux.control:open-connection`

**Capturing and querying.** `libtmux:fetch-snapshot` captures sessions,
windows, panes, window links and attached clients as one graph that stays
usable after the client closes; it is an interval observation, not a
transaction. `libtmux:fetch-sessions`, `libtmux:fetch-windows`,
`libtmux:fetch-panes` and `libtmux:fetch-clients` each take a fresh snapshot
and return one collection, and `libtmux:refresh` returns a replacement
observation without changing the earlier one. The optional query package
filters a capture locally: `libtmux.query:compile-filter` compiles a filter
form without evaluating it as Lisp, `libtmux.query:matching` returns the
values it accepts, and `libtmux.query:one` and `libtmux.query:one-or-none`
take the single result.

`libtmux:fetch-snapshot`, `libtmux:fetch-sessions`, `libtmux:fetch-windows`,
`libtmux:fetch-panes`, `libtmux:fetch-clients`, `libtmux:refresh`,
`libtmux.query:compile-filter`, `libtmux.query:matching`, `libtmux.query:one`
and `libtmux.query:one-or-none`

**Creating, restarting and removing.** `libtmux:new-session` creates a
detached session on a daemon that is already running; it never starts or
replaces one. `libtmux:new-window` adds a window to a captured session and
`libtmux:split-pane` splits a captured pane, and `libtmux:outcome-value`
supplies the created object from each result. `libtmux:respawn-pane` restarts
a pane's process in place, and `libtmux:respawn-window` restarts a window as a
single pane. `libtmux:kill-pane`, `libtmux:kill-window` and
`libtmux:kill-session` delete exactly the captured target, while
`libtmux:kill-server` terminates the daemon, which `libtmux:close-client`
never does.

`libtmux:new-session`, `libtmux:new-window`, `libtmux:split-pane`,
`libtmux:outcome-value`, `libtmux:respawn-pane`, `libtmux:respawn-window`,
`libtmux:kill-pane`, `libtmux:kill-window`, `libtmux:kill-session`,
`libtmux:kill-server` and `libtmux:close-client`

**Selecting, renaming and arranging.** Each operation takes captured targets
and changes what is selected, how sessions, windows and panes are named, sized
and laid out, or where they sit. Most also take an observe argument, true by
default, whose replacement record `libtmux:outcome-value` returns; earlier
captures stay unchanged. `libtmux:select-layout` applies a named or custom
layout, and `libtmux:swap-windows`, `libtmux:move-window`,
`libtmux:link-window` and `libtmux:unlink-window` work on window links.

`libtmux:select-window`, `libtmux:select-pane`, `libtmux:next-window`,
`libtmux:previous-window`, `libtmux:last-window`, `libtmux:last-pane`,
`libtmux:rename-window`, `libtmux:rename-session`, `libtmux:select-layout`,
`libtmux:next-layout`, `libtmux:previous-layout`, `libtmux:resize-pane`,
`libtmux:resize-window`, `libtmux:rotate-window`, `libtmux:swap-panes`,
`libtmux:swap-windows`, `libtmux:move-pane`, `libtmux:join-pane`,
`libtmux:break-pane`, `libtmux:move-window`, `libtmux:link-window`,
`libtmux:unlink-window` and `libtmux:outcome-value`

**Reading and driving panes.** `libtmux:capture-pane` reads a pane as strict
UTF-8 text and signals a decoding error otherwise, and
`libtmux:capture-pane-bytes` returns the octets unchanged. `libtmux:send-text`
sends literal text, `libtmux:send-keys` interprets tmux key names such as C-c
and Enter, and `libtmux:send-prefix` sends the session's prefix key. A
completed send means tmux processed the request, not that the application
consumed it. `libtmux:clear-history`, `libtmux:copy-mode` and
`libtmux:pipe-pane` clear a pane's history, enter or leave copy mode, and set
up a tmux-owned pipe.

`libtmux:capture-pane`, `libtmux:capture-pane-bytes`, `libtmux:send-text`,
`libtmux:send-keys`, `libtmux:send-prefix`, `libtmux:clear-history`,
`libtmux:copy-mode` and `libtmux:pipe-pane`

**Options, hooks and environment.** `libtmux:set-option`, `libtmux:set-hook`
and `libtmux:set-environment` write one entry, and every operation here
requires a scope, with a captured target for a session, window or pane.
`libtmux:show-option` returns one decoded option with a presence flag,
`libtmux:show-options` returns decoded records for several, and
`libtmux:show-hooks` and `libtmux:show-environment` do the same for hooks and
environment entries. `libtmux:show-options-text` and its hook and environment
counterparts return tmux's printer text instead. `libtmux:unset-environment`
deletes a name, while `libtmux:remove-environment` stores tmux's removal
marker.

`libtmux:set-option`, `libtmux:unset-option`, `libtmux:show-option`,
`libtmux:show-options`, `libtmux:show-options-text`, `libtmux:set-hook`,
`libtmux:unset-hook`, `libtmux:show-hooks`, `libtmux:show-hooks-text`,
`libtmux:set-environment`, `libtmux:unset-environment`,
`libtmux:remove-environment`, `libtmux:show-environment` and
`libtmux:show-environment-text`

**Buffers.** `libtmux:set-buffer` and `libtmux:load-buffer` store a string,
octets or a file's bytes; `libtmux:show-buffer`, `libtmux:save-buffer` and
`libtmux:paste-buffer` read a buffer's octets, write them to a file or paste
them into a pane. `libtmux:list-buffers` returns each buffer's name, size and
creation time, and `libtmux:delete-buffer` deletes one. Without a name, show,
save, paste and delete use tmux's top buffer, while store and load create an
automatic name; deleting by name needs tmux 3.4 or newer.

`libtmux:set-buffer`, `libtmux:load-buffer`, `libtmux:show-buffer`,
`libtmux:save-buffer`, `libtmux:paste-buffer`, `libtmux:list-buffers` and
`libtmux:delete-buffer`

**Attached terminals, key bindings and the rest.** `libtmux:switch-client`,
`libtmux:detach-client` and the other terminal operations act on one attached
terminal taken from a capture, while `libtmux:lock-session` and
`libtmux:lock-server` lock a session's or every attached terminal.
`libtmux:bind-key` and `libtmux:unbind-key` change key bindings and
`libtmux:server-access` changes the daemon's access list; `libtmux:list-keys`,
`libtmux:list-commands` and `libtmux:list-server-access` print bindings,
built-in commands and the access list. `libtmux:wait-for` waits on, signals or
locks a channel, though waiting and locking need tmux 3.8, and
`libtmux:display-message` prints a message through tmux. `libtmux:run-command`
runs explicit tmux arguments for anything else; it does not check captured
targets.

`libtmux:switch-client`, `libtmux:detach-client`, `libtmux:refresh-client`,
`libtmux:suspend-client`, `libtmux:lock-client`, `libtmux:lock-session`,
`libtmux:lock-server`, `libtmux:bind-key`, `libtmux:unbind-key`,
`libtmux:server-access`, `libtmux:list-keys`, `libtmux:list-commands`,
`libtmux:list-server-access`, `libtmux:wait-for`, `libtmux:display-message`
and `libtmux:run-command`"))

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
Checks the runtime profile and required OS facilities before resolving PROGRAM.
An unsupported profile or facility signals UNSUPPORTED-PLATFORM; ERROR-FEATURE
identifies the requirement. PROGRAM must resolve to a native x86_64 ELF tmux
executable; pass the underlying binary when PATH selects a script or shim.
SOCKET-NAME and SOCKET-PATH are mutually exclusive; omission selects tmux's
default socket. No daemon is started. TIMEOUT is seconds; OUTPUT-LIMIT bounds
combined stdout/stderr bytes per command. Signals an operational condition on
version/launch failure. Returned configuration strings are owned by the client.
See also: WITH-CLIENT, CLOSE-CLIENT, UNSUPPORTED-PLATFORM, ERROR-FEATURE."
  (libtmux.internal::require-process-profile)
  (libtmux.internal::check-limits timeout output-limit)
  (when (and socket-name socket-path)
    (libtmux.internal::invalid-argument "Specify socket-name or socket-path, not both"))
  (dolist (value (list socket-name socket-path config-file))
    (when value
      (unless (and (stringp value) (plusp (length value)) (not (find #\Null value)))
        (libtmux.internal::invalid-argument "Socket/configuration values must be nonempty strings without NUL"))))
  (libtmux.internal::ensure-process-platform)
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
