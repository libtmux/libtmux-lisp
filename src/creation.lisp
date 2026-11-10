(in-package #:libtmux.internal)

(defun creation-options (cwd environment command shell-command command-p shell-command-p)
  (append (when cwd (list "-c" (literal-format (text-argument cwd "Working directory" nil))))
          (environment-arguments environment) '("--")
          (pane-command-arguments command shell-command :command-p command-p :shell-command-p shell-command-p)))

(defun observe-created (model)
  (lambda (outcome capture)
    (let* ((text (outcome-text outcome))
           (field (ecase model (:session :session/id) (:window :window/id) (:pane :pane/id))))
      (unless (and (plusp (length text)) (char= #\Newline (char text (1- (length text)))))
        (error 'libtmux:decoding-error :outcome outcome :message "Creation did not return one entity ID"))
      (let* ((id (decode-scalar (registered-field field model) (subseq text 0 (1- (length text)))))
             (entity (find id (captured-collection capture model) :key #'libtmux:id :test #'equal)))
        (unless entity
          (error 'libtmux:stale-target :outcome outcome
                 :message "Creation succeeded but the resulting entity is no longer present"))
        (values entity t)))))

(in-package #:libtmux)

(defun new-window (client session &key name index cwd environment
                                      (command nil command-p) (shell-command nil shell-command-p)
                                      (detached t) cancel-token timeout output-limit)
  "Create a physical window in captured SESSION and return a COMMAND-OUTCOME.
NAME and CWD are literal strings. INDEX chooses a free link index; omission uses
tmux's next available index. DETACHED defaults true. ENVIRONMENT is a list/vector
of (name . value) string pairs. COMMAND is nonempty argv; SHELL-COMMAND is a
separate, mutually exclusive shell string. Omit both for tmux's default shell.
OUTCOME-VALUE supplies the resulting window; observation failure is separate.
Never replaces an occupied index or retries a mutation. Limits cover all I/O."
  (let ((target (libtmux.internal::physical-target session :session)))
    (libtmux.internal::perform-command
     client (list session)
     (append (list "new-window" "-P" "-F" "#{window_id}" "-t"
                   (concatenate 'string target ":"
                                (if index (libtmux.internal::integer-argument index 0 2147483647 "Window index") "")))
             (when detached '("-d"))
             (when name (list "-n" (libtmux.internal::literal-format name)))
             (libtmux.internal::creation-options cwd environment command shell-command command-p shell-command-p))
     :observe (libtmux.internal::observe-created :window)
     :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun split-pane (client pane &key (direction :vertical) size percent before full-size
                                   cwd environment (detached t)
                                   (command nil command-p) (shell-command nil shell-command-p)
                                   cancel-token timeout output-limit)
  "Split captured PANE and return a COMMAND-OUTCOME with the created pane.
DIRECTION is :HORIZONTAL (left/right) or :VERTICAL (top/bottom). SIZE is a
positive cell count; PERCENT is 1 through 100, mutually exclusive with SIZE.
BEFORE places the pane before its target; FULL-SIZE spans the whole window.
DETACHED defaults true. CWD, ENVIRONMENT, COMMAND and SHELL-COMMAND follow
NEW-WINDOW. Failed acquisition after successful creation is retained separately.
Signals STALE-TARGET or an operational condition; never retries the mutation."
  (libtmux.internal::perform-command
   client (list pane)
   (append (list "split-window" "-P" "-F" "#{pane_id}" "-t" (libtmux.internal::physical-target pane :pane))
           (libtmux.internal::split-flags direction size percent before full-size detached)
           (libtmux.internal::creation-options cwd environment command shell-command command-p shell-command-p))
   :observe (libtmux.internal::observe-created :pane)
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun new-session (client &key name window-name width height cwd environment
                               (command nil command-p) (shell-command nil shell-command-p)
                               cancel-token timeout output-limit)
  "Create a detached session on the selected live daemon; return a COMMAND-OUTCOME.
NAME, WINDOW-NAME and CWD are literal. WIDTH/HEIGHT are positive initial cell
dimensions through 65535. ENVIRONMENT, COMMAND and SHELL-COMMAND follow
NEW-WINDOW. OUTCOME-VALUE supplies the created session; acquisition failure is
retained separately. This operation requires an existing daemon and never
silently starts or replaces one.
See also: START-DAEMON, WITH-DAEMON, NEW-WINDOW."
  (libtmux.internal::perform-command
   client nil
   (append '("new-session" "-d" "-P" "-F" "#{session_id}")
           (when name (list "-s" (libtmux.internal::literal-format name)))
           (when window-name (list "-n" (libtmux.internal::literal-format window-name)))
           (when width (list "-x" (libtmux.internal::integer-argument width 1 65535 "Width")))
           (when height (list "-y" (libtmux.internal::integer-argument height 1 65535 "Height")))
           (libtmux.internal::creation-options cwd environment command shell-command command-p shell-command-p))
   :observe (libtmux.internal::observe-created :session)
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))
