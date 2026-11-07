(in-package #:libtmux.tests)

(in-suite unit)

(test configuration-catalogs-preserve-version-authority
  (let* ((old (libtmux.internal::configuration-catalog "3.3a"))
         (new (libtmux.internal::configuration-catalog "3.8")))
    (is (= 181 (length (libtmux.internal::catalog-option-names old))))
    (is (= 272 (length (libtmux.internal::catalog-option-names new))))
    (signals libtmux:libtmux-error (libtmux.internal::configuration-catalog "3.8a"))
    (signals libtmux:invalid-argument
      (libtmux.internal::catalog-option old "display-panes-time" :window))
    (is (eq :number (libtmux.internal::option-spec-kind
                    (libtmux.internal::catalog-option new "display-panes-time" :window))))
    (is (eq :colour (libtmux.internal::option-spec-kind
                    (libtmux.internal::catalog-option old "cursor-colour" :pane))))
    (is (eq :string (libtmux.internal::option-spec-kind
                    (libtmux.internal::catalog-option new "cursor-color" :pane))))
    (signals libtmux:invalid-argument
      (libtmux.internal::catalog-option new "after-queue" :session))
    (is (not (libtmux.internal::option-spec-hook-p
              (libtmux.internal::catalog-option new "default-client-command" :server))))
    (signals libtmux:invalid-argument
      (libtmux.internal::catalog-option new "@event" :server :hooks-only t))
    (is (eq :string (libtmux.internal::option-spec-kind
                    (libtmux.internal::catalog-option new "@event" :server))))
    (let ((names (libtmux.internal::catalog-option-names new :scope :server)))
      (fill (aref names 0) #\X)
      (is (not (string= (aref names 0)
                        (aref (libtmux.internal::catalog-option-names new :scope :server) 0)))))))

(test configuration-values-follow-declared-domains
  (let* ((catalog (libtmux.internal::configuration-catalog "3.8"))
         (number (libtmux.internal::catalog-option catalog "input-buffer-size" :server))
         (choice (libtmux.internal::catalog-option catalog "status" :session))
         (flag (libtmux.internal::catalog-option catalog "mouse" :session))
         (user (libtmux.internal::catalog-option catalog "@mode" :pane)))
    (is (= 4294967295 (libtmux.internal::normalize-option-value number 4294967295)))
    (dolist (value (list 4294967296 -1 1/2 1.0))
      (signals libtmux:invalid-argument (libtmux.internal::normalize-option-value number value)))
    (is (string= "2" (libtmux.internal::normalize-option-value choice "2")))
    (signals libtmux:invalid-argument (libtmux.internal::normalize-option-value choice 2))
    (is (null (libtmux.internal::normalize-option-value flag nil)))
    (signals libtmux:invalid-argument (libtmux.internal::normalize-option-value flag "off"))
    (is (string= "off" (libtmux.internal::normalize-option-value user "off")))
    (let* ((source (copy-seq "off"))
           (value (libtmux.internal::normalize-option-value user source)))
      (fill source #\X)
      (is (string= "off" value)))))

(test configuration-array-keys-retain-native-version-semantics
  (let ((old (libtmux.internal::configuration-catalog "3.7c"))
        (new (libtmux.internal::configuration-catalog "3.8")))
    (is (string= "2147483647" (libtmux.internal::normalize-option-key old 2147483647)))
    (signals libtmux:invalid-argument (libtmux.internal::normalize-option-key old 2147483648))
    (signals libtmux:invalid-argument (libtmux.internal::normalize-option-key old "name"))
    (is (string= "4294967295" (libtmux.internal::normalize-option-key new 4294967295)))
    (is (string= "7" (libtmux.internal::normalize-option-key new "0007")))
    (is (string= "name 雪" (libtmux.internal::normalize-option-key new "name 雪")))
    (let ((zero (libtmux.internal::normalize-option-key new "0000")))
      (fill zero #\X)
      (is (string= "0" (libtmux.internal::normalize-option-key new "00"))))
    (dolist (key '("" "4294967296" -1 1/2))
      (signals libtmux:invalid-argument (libtmux.internal::normalize-option-key new key)))))

(test configuration-mutations-select-the-live-witness-catalog
  (let* ((old (libtmux.internal::make-server-witness :version "3.7c"))
         (new (libtmux.internal::make-server-witness :version "3.8"))
         (string-key
           (libtmux.internal::configuration-mutation-builder
            "set-option" :server '("-s") "command-alias" "display=list-sessions" t
            "named" t nil nil nil nil))
         (alias
           (libtmux.internal::configuration-mutation-builder
            "set-option" :pane '("-p" "-t" "%1") "cursor-color" "red" t
            nil nil nil nil nil nil))
         (hook
           (libtmux.internal::configuration-mutation-builder
            "set-hook" :session '("-t" "$1") "after-new-window"
            "display-message ready" t nil nil nil nil t nil)))
    (signals libtmux:invalid-argument (funcall string-key old nil))
    (is (equal '("set-option" "-s" "--" "command-alias[named]"
                 "display=list-sessions")
               (funcall string-key new nil)))
    (is (equal '("set-option" "-p" "-t" "%1" "--" "cursor-colour" "red")
               (funcall alias new nil)))
    (let ((arguments (funcall hook new nil)))
      (is (equal '("set-hook" "-t" "$1" "--" "after-new-window"
                   "display-message ready")
                 arguments))
      (is (not (member "-R" arguments :test #'string=))))
    (signals libtmux:invalid-argument
      (funcall
       (libtmux.internal::configuration-mutation-builder
        "set-option" :session '("-t" "$1") "prefix" "C-b" t
        nil nil nil t nil nil)
       new nil))
    (signals libtmux:invalid-argument
      (funcall
       (libtmux.internal::configuration-mutation-builder
        "set-hook" :session '("-t" "$1") "after-new-window"
        "display-message ready" t 0 t nil t t nil)
       new nil))
    (signals libtmux:invalid-argument
      (funcall
       (libtmux.internal::configuration-mutation-builder
        "set-option" :session '("-t" "$1") "after-new-window"
        "display-message ready" t nil nil nil nil nil nil)
       new nil))))
