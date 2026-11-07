(defpackage #:libtmux
  (:use #:cl)
  (:documentation "Native captured tmux objects and explicit external operations.")
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
