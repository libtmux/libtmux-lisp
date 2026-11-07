(in-package #:libtmux)

(defun send-text (client pane text &key enter cancel-token timeout output-limit)
  "Send literal TEXT to PANE through tmux and return a COMMAND-OUTCOME.
ENTER appends one Return key in the same command. Text such as C-c remains
literal text; it is not parsed as a key name, tmux format or shell command.
Tmux's active pane mode still handles the resulting input. Completion means
tmux processed the send request, not that the application consumed it. An
oversized encoded command is rejected without silently splitting the input."
  (let ((text (libtmux.internal::text-argument text)))
    (libtmux.internal::perform-command
     client (list pane)
     (list "send-keys" "-l" "-t" (libtmux.internal::physical-target pane :pane) "--"
           (if enter (concatenate 'string text (string #\Return)) text))
     :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun send-keys (client pane keys &key (repeat 1) cancel-token timeout output-limit)
  "Send a finite nonempty list/vector of tmux key strings to PANE.
Return a COMMAND-OUTCOME. REPEAT is a positive count. Tmux interprets key names
such as C-c and Enter; its unrecognized strings fall back to literal input.
Use SEND-TEXT when key-name interpretation must be disabled. Acknowledgment
does not prove application readiness or consumption."
  (let ((keys (libtmux.internal::argument-vector keys)))
    (unless (and (plusp (length keys)) (every (lambda (key) (plusp (length key))) keys))
      (libtmux.internal::invalid-argument "Keys must be a nonempty sequence of nonempty strings"))
    (libtmux.internal::perform-command
     client (list pane)
     (append (list "send-keys" "-t" (libtmux.internal::physical-target pane :pane)
                   "-N" (libtmux.internal::integer-argument repeat 1 4294967295 "Repeat count") "--")
             (coerce keys 'list))
     :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun send-prefix (client pane &key second cancel-token timeout output-limit)
  "Send the session's configured prefix key to PANE; return a COMMAND-OUTCOME.
SECOND selects prefix2. Tmux's active pane mode handles input; completion does
not establish application consumption. Signals STALE-TARGET or an operational
condition retaining its outcome."
  (libtmux.internal::perform-command
   client (list pane)
   (append (list "send-prefix" "-t" (libtmux.internal::physical-target pane :pane))
           (when second '("-2")))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun clear-history (client pane &key cancel-token timeout output-limit)
  "Clear PANE's retained tmux history; return a COMMAND-OUTCOME.
Captured observations remain unchanged. This does not promise to clear the
application's current screen. Signals STALE-TARGET or an operational condition."
  (libtmux.internal::perform-command
   client (list pane) (list "clear-history" "-t" (libtmux.internal::physical-target pane :pane))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun copy-mode (client pane &key exit page-up cancel-token timeout output-limit)
  "Enter PANE's tmux copy mode, or EXIT it; return a COMMAND-OUTCOME.
PAGE-UP scrolls up on entry and cannot be combined with EXIT. This addresses an
existing pane and does not create an interactive terminal frontend. Signals
STALE-TARGET or an operational condition."
  (when (and exit page-up)
    (libtmux.internal::invalid-argument "Copy-mode exit and page-up are mutually exclusive"))
  (libtmux.internal::perform-command
   client (list pane)
   (append (list "copy-mode" "-t" (libtmux.internal::physical-target pane :pane))
           (when exit '("-q")) (when page-up '("-u")))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))
