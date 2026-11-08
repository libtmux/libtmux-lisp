(in-package #:libtmux.tests)

(in-suite integration)

(test command-and-key-printer-profiles
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (multiple-value-bind (text outcome)
          (libtmux:list-commands client :command "ls" :format "#{command_list_name}|%Y")
        (is (equal (format nil "list-sessions|%Y~%") text))
        (is (eq :succeeded (libtmux:outcome-status outcome))))
      (is (search "list-sessions" (libtmux:list-commands client)))
      (if (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.6")
          (progn
            (is (equal (format nil "rename-window~%")
                       (libtmux:list-commands client :command "rename-w"
                                                     :format "#{command_list_name}")))
            (signals libtmux:command-failed
              (libtmux:list-commands client :command "missing-libtmux-command")))
          (progn
            (is (equal "" (libtmux:list-commands client :command "rename-w")))
            (is (equal "" (libtmux:list-commands client :command "missing-libtmux-command")))))
      (let ((table "literal-#{pid};λ")
            (note (format nil "note-#{pid};λ'~%second line"))
            (status-row-p
              (and (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.7")
                   (not (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8")))))
        (is (eq :succeeded
                (libtmux:outcome-status
                 (libtmux:bind-key client "x" :table table :note note :repeat t
                                              :command '("display-message" "-p" "binding-command")))))
        (if status-row-p
            (progn
              (is (equal "" (libtmux:list-keys client :table table :key "x")))
              (is (equal "" (fixture-ok fixture "list-keys" "-N" "-T" table "x"))))
            (progn
              (is (search "binding-command" (libtmux:list-keys client :table table :key "x")))
              (is (search note (fixture-ok fixture "list-keys" "-N" "-T" table "x")))))
        (if (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.7")
            (is (equal (if status-row-p "" (format nil "key-%Y~%"))
                       (libtmux:list-keys client :table table :format "key-%Y")))
            (handler-case
                (progn (libtmux:list-keys client :table table :format "key-%Y")
                       (fail "An older daemon admitted formatted key listing"))
              (libtmux:unsupported-capability (condition)
                (is (eq :not-dispatched
                        (libtmux:outcome-status (libtmux:error-outcome condition)))))))
        (signals libtmux:command-failed (libtmux:list-keys client :table table :key "F20"))
        (if status-row-p
            (is (equal "" (libtmux:list-keys client :table table :key "y")))
            (signals libtmux:command-failed (libtmux:list-keys client :table table :key "y")))
        (libtmux:bind-key client "y" :table table :note "second binding"
                                     :command '("display-message" "-p" "second-command"))
        (is (search "binding-command" (libtmux:list-keys client :table table)))
        (is (search note (fixture-ok fixture "list-keys" "-N" "-T" table)))
        (when (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.7")
          (is (equal (format nil "key-%Y~%key-%Y~%")
                     (libtmux:list-keys client :table table :format "key-%Y"))))
        (libtmux:unbind-key client "y" :table table)
        (is (eq :succeeded (libtmux:outcome-status (libtmux:unbind-key client "x" :table table))))
        (signals libtmux:command-failed (libtmux:unbind-key client "x" :table table)))
      (handler-case
          (progn
            (libtmux:bind-key client "x" :command-source
                             "LIBTMUX_BIND_PARSE=retained; missing-libtmux-command")
            (fail "Invalid binding source succeeded"))
        (libtmux:outcome-unknown (condition)
          (is (eq :unknown (libtmux:outcome-status (libtmux:error-outcome condition))))
          (is (eq :missing-completion-receipt
                  (libtmux:outcome-reason (libtmux:error-outcome condition))))))
      (is (equal (format nil "LIBTMUX_BIND_PARSE=retained~%")
                 (fixture-ok fixture "show-environment" "-g" "LIBTMUX_BIND_PARSE"))))))

(test key-bindings-run-on-frontend-events
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((value (format nil "λ; $HOME \"q\" \\ #{pid} #[x];~%  %Y")))
        (fixture-ok fixture "set-option" "-g" "@expected" value)
        (fixture-ok fixture "set-hook" "-g" "after-set-option" "wait-for -S key-value")
        (libtmux:bind-key client "-" :table "root"
                         :command (list "set-option" "-g" "@binding" value))
        (libtmux:bind-key client "x" :table "root" :command-source "wait-for -S key-barrier")
        (is (equal "" (fixture-ok fixture "show-options" "-gqv" "@binding")))
        (call-with-attached-terminal-client
         fixture
         (lambda (terminal)
           (labels ((press (keys channel)
                      (let* ((bytes (libtmux.internal::encode-utf8 keys))
                             (fd (sb-sys:fd-stream-fd
                                  (sb-ext:process-pty (terminal-client-process terminal)))))
                        (sb-sys:with-pinned-objects (bytes)
                          (is (= (length bytes) (sb-posix:write fd (sb-sys:vector-sap bytes)
                                                               (length bytes)))))
                        (is (eq :succeeded
                                (libtmux:outcome-status
                                 (libtmux.internal::run-process
                                  (list (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                        "-N" "-S" (fixture-socket fixture) "wait-for" channel)
                                  :timeout 0.5)))))))
             (press "-" "key-value")
             ;; Some native printers escape $. Compare stored values instead.
             (is (equal (format nil "1~%")
                        (fixture-ok fixture "display-message" "-p"
                                    "#{==:#{@binding},#{@expected}}")))
             (libtmux:bind-key client "-" :table "root"
                              :command-source "set-option -g @binding replaced")
             (press "-" "key-value")
             (is (equal (format nil "replaced~%")
                        (fixture-ok fixture "display-message" "-p" "#{@binding}")))
             (libtmux:unbind-key client "-" :table "root")
             (fixture-ok fixture "set-hook" "-gu" "after-set-option")
             (fixture-ok fixture "set-option" "-g" "@binding" "sentinel")
             ;; The following bound key acknowledges processing of both bytes.
             (press "-x" "key-barrier")
             (is (equal (format nil "sentinel~%")
                        (fixture-ok fixture "display-message" "-p" "#{@binding}"))))))))))
