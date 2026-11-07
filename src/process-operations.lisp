(in-package #:libtmux.internal)

(defun respawn-entity (client target model kill cwd environment command shell-command
                      command-p shell-command-p observe options)
  (apply #'perform-command client (list target)
         (append (list (ecase model (:window "respawn-window") (:pane "respawn-pane"))
                       "-t" (physical-target target model))
                 (when kill '("-k"))
                 (creation-options cwd environment command shell-command command-p shell-command-p))
         :observe (when observe (observe-target client target)) options))

(defun literal-time-format (text)
  (let ((literal (literal-format text)))
    (when (> (length (encode-utf8 literal)) 8191)
      (invalid-argument "Literal pipe command exceeds tmux's 8,191-byte time-format capacity"))
    (with-output-to-string (stream)
      (loop for character across literal
            do (when (char= character #\%) (write-char #\% stream))
               (write-char character stream)))))

(in-package #:libtmux)

(defun respawn-pane (client pane &key kill cwd environment (observe t)
                                    (command nil command-p) (shell-command nil shell-command-p)
                                    cancel-token timeout output-limit)
  "Restart PANE's process and return a COMMAND-OUTCOME.
KILL explicitly replaces a running process; otherwise tmux requires it to have
exited. Omit COMMAND and SHELL-COMMAND to reuse the previous command. Explicit
argv, shell text, literal CWD and ENVIRONMENT follow NEW-WINDOW. OBSERVE returns
a replacement pane through OUTCOME-VALUE; its earlier capture stays unchanged.
The process may exit before observation. Signals STALE-TARGET or an operational
condition; never retries an uncertain restart."
  (libtmux.internal::respawn-entity
   client pane :pane kill cwd environment command shell-command command-p shell-command-p observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun respawn-window (client window &key kill cwd environment (observe t)
                                        (command nil command-p) (shell-command nil shell-command-p)
                                        cancel-token timeout output-limit)
  "Restart WINDOW as one pane and return a COMMAND-OUTCOME.
KILL explicitly replaces running processes. Tmux retains its first pane and
destroys every other pane in the physical window, including through other links.
Other options follow RESPAWN-PANE. OBSERVE supplies a replacement window without
changing earlier observations. Linked-window session context is selected by tmux.
Signals STALE-TARGET or an operational condition; never retries the restart."
  (libtmux.internal::respawn-entity
   client window :window kill cwd environment command shell-command command-p shell-command-p observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun pipe-pane (client pane &key shell-command format-p (direction :output) toggle
                                 cancel-token timeout output-limit)
  "Configure PANE's tmux-owned pipe and return a COMMAND-OUTCOME.
SHELL-COMMAND is shell source, literal to tmux by default; FORMAT-P explicitly
enables tmux format and time expansion before shell execution. DIRECTION is
:OUTPUT (pane to shell), :INPUT (shell to pane), or :BOTH. Omit SHELL-COMMAND,
or pass an empty string, to close the pipe. TOGGLE closes an existing pipe
without starting its replacement. Replacing a pipe closes the previous one.
Completion acknowledges configuration, not shell startup, success or output
consumption. The daemon owns the pipe child; closing CLIENT leaves it running.
Literal commands exceeding tmux's time-format capacity fail before I/O.
Signals STALE-TARGET or an operational condition; never retries configuration."
  (unless (member direction '(:input :output :both))
    (libtmux.internal::invalid-argument "Pipe direction must be :input, :output or :both"))
  (libtmux.internal::perform-command
   client (list pane)
   (append (list "pipe-pane" "-t" (libtmux.internal::physical-target pane :pane))
           (ecase direction (:input '("-I")) (:output '("-O")) (:both '("-I" "-O")))
           (when toggle '("-o"))
           (when shell-command
             (list "--" (if format-p
                            (libtmux.internal::text-argument shell-command "Pipe shell format")
                            (libtmux.internal::literal-time-format shell-command)))))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))
