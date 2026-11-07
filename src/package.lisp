(defpackage #:libtmux
  (:use #:cl)
  (:documentation "Native Common Lisp captured tmux graphs and explicit external operations.
OPEN-CLIENT/WITH-CLIENT establish connection scopes without starting a daemon.
FETCH-SNAPSHOT acquires sessions, physical windows, panes, window links and
attached clients. Captured getters, traversal and ENTITY-DATA are local and
remain usable after closure; captured strings and containers are owned copies. REFRESH returns
a new observation. Named mutators take CLIENT first and return COMMAND-OUTCOME;
OUTCOME-VALUE and FIELD-VALUE return value and presence as two values.
Operations are synchronous, bounded and cancellable, with one active operation
per client. Typed LIBTMUX-ERROR conditions retain diagnostic outcome and cause.
Closing a client releases owned resources and leaves the daemon alive.
See docs/index.md for the tutorial, API reference and current capability limits.")
  (:export
   #:libtmux-error #:error-message #:error-cause #:error-outcome #:error-client
   #:invalid-argument #:unsupported-platform #:unsupported-tmux
   #:unsupported-configuration #:error-setting #:error-commands
   #:unsupported-capability #:error-feature #:error-required-version #:error-actual-version
   #:client-closed #:client-busy #:cleanup-failed #:command-failed
   #:outcome-unknown #:command-cancelled #:deadline-exceeded
   #:output-limit-exceeded #:decoding-error
   #:incomplete-snapshot #:field-unavailable #:error-field #:error-model
   #:stale-target #:error-target
   #:snapshot #:entity #:session #:window #:pane #:window-link #:attached-client
   #:entity-model #:field-value #:entity-data #:id #:provenance #:same-entity-p
   #:sessions #:windows #:panes #:window-links #:clients
   #:name #:active-p #:width #:height #:index #:current-command #:current-path #:title #:dead-p
   #:fetch-snapshot #:fetch-sessions #:fetch-windows #:fetch-panes #:fetch-clients #:refresh
   #:rename-window #:rename-session #:select-window #:select-pane #:capture-pane #:capture-pane-bytes
   #:new-session #:new-window #:split-pane
   #:send-text #:send-keys #:send-prefix #:clear-history #:copy-mode
   #:respawn-pane #:respawn-window #:pipe-pane
   #:resize-pane #:resize-window #:select-layout #:next-layout #:previous-layout
   #:next-window #:previous-window #:last-window #:last-pane
   #:link-window #:unlink-window #:move-window #:swap-windows
   #:move-pane #:join-pane #:break-pane #:swap-panes #:rotate-window
   #:list-buffers #:set-buffer #:show-buffer #:load-buffer #:save-buffer #:paste-buffer #:delete-buffer
   #:set-option #:unset-option #:set-hook #:unset-hook
   #:set-environment #:unset-environment #:remove-environment
   #:kill-pane #:kill-window #:kill-session #:kill-server
   #:command-outcome #:outcome-status #:outcome-phase #:outcome-arguments
   #:outcome-stdout #:outcome-stderr #:outcome-exit-code #:outcome-reason
   #:outcome-elapsed #:outcome-value #:outcome-observation-error
   #:outcome-cleanup-failures
   #:cancellation-token #:make-cancellation-token #:cancel #:cancelled-p
   #:client #:open-client #:close-client #:with-client #:client-open-p
   #:client-cleanup-failures #:tmux-version #:run-command))

(defpackage #:libtmux.internal
  (:use #:cl)
  (:documentation "Implementation protocol; no compatibility promise."))
