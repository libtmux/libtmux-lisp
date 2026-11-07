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
