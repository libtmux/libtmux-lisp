(in-package #:libtmux.internal)

(defparameter *reserved-command-names*
  '("bind-key" "break-pane" "capture-pane" "clear-history" "copy-mode"
    "delete-buffer" "detach-client" "display-message" "if-shell" "join-pane"
    "kill-pane" "kill-server" "kill-session" "kill-window" "last-pane" "last-window"
    "link-window" "list-buffers" "list-clients" "list-commands" "list-keys"
    "list-panes" "list-sessions" "list-windows" "load-buffer" "lock-client"
    "lock-server" "lock-session" "move-pane" "move-window" "new-session" "new-window"
    "next-layout" "next-window" "paste-buffer" "pipe-pane" "previous-layout"
    "previous-window" "refresh-client" "rename-session" "rename-window"
    "resize-pane" "resize-window" "respawn-pane" "respawn-window" "rotate-window"
    "run-shell" "save-buffer" "select-layout" "select-pane" "select-window"
    "send-keys" "send-prefix" "server-access" "set-buffer" "set-environment"
    "libtmux-internal-read-server-refused" "libtmux-internal-read-target-refused"
    "set-hook" "set-option" "show-buffer" "show-environment" "show-hooks"
    "show-options" "source-file" "split-window" "suspend-client" "swap-pane"
    "swap-window" "switch-client" "unbind-key" "unlink-window" "wait-for"))

(defun check-command-aliases (text outcome)
  (let ((conflicts nil))
    (dolist (line (uiop:split-string text :separator '(#\Newline)))
      (let ((equals (position #\= line)))
        (when equals
          (let ((name (subseq line 0 equals)))
            (when (member name *reserved-command-names* :test #'string=)
              (pushnew name conflicts :test #'string=))))))
    (when conflicts
      (setf conflicts (sort conflicts #'string<))
      (error 'libtmux:unsupported-configuration :setting :command-alias
             :commands conflicts :outcome outcome
             :message (format nil "command-alias overrides reserved built-ins: ~{~A~^, ~}; remove those overrides before using named APIs"
                              conflicts)))))

(defun audit-command-aliases (client token timeout output-limit)
  ;; SHOW-OPTIONS is the trusted bootstrap spelling; this cannot audit its own
  ;; arbitrary override or atomically exclude later configuration changes.
  (let ((outcome (check-outcome
                  (execute-tmux client '("-N" "show-options" "-s" "-v" "command-alias")
                                token timeout output-limit nil))))
    (handler-bind ((libtmux:libtmux-error
                     (lambda (condition) (setf (slot-value condition 'libtmux::outcome) outcome))))
      (check-command-aliases (strict-text (libtmux:outcome-stdout outcome)) outcome))
    outcome))
