(in-package #:libtmux.tests)

(in-suite unit)

(test process-environment-validation-and-ownership
  (let* ((entry (copy-seq "KEY=value=with=equals"))
         (input (vector entry "EMPTY="))
         (owned (libtmux.internal::owned-process-environment input)))
    (setf (char entry 4) #\X (aref input 1) "OTHER=changed")
    (is (equal '("KEY=value=with=equals" "EMPTY=") owned)))
  (is (null (libtmux.internal::owned-process-environment nil)))
  (dolist (input (list '("NO_SEPARATOR") '("=empty-name") '("K=first" "K=second")
                      (list (format nil "K=~C" #\Null)) '("K=v" . :improper)
                      (make-array 4097 :initial-element "K=v")
                      (list (concatenate 'string "K=" (make-string 32768 :initial-element #\λ)))
                      (loop for i below 17 collect
                            (format nil "K~D=~A" i (make-string 65530 :initial-element #\x)))))
    (signals libtmux:invalid-argument (libtmux.internal::owned-process-environment input)))
  (let ((cyclic (list "K=v")))
    (setf (cdr cyclic) cyclic)
    (signals libtmux:invalid-argument (libtmux.internal::owned-process-environment cyclic)))
  (signals libtmux:invalid-argument (libtmux.internal::owned-working-directory ""))
  (signals libtmux:invalid-argument (libtmux.internal::owned-working-directory "/dev/null")))

(test outcome-value-owns-returned-data
  (let* ((outcome (make-instance 'libtmux:command-outcome
                                 :value (vector (list (copy-seq "retained"))) :present-p t))
         (first (libtmux:outcome-value outcome)))
    (setf (char (first (aref first 0)) 0) #\X
          (aref first 0) nil)
    (multiple-value-bind (value present-p) (libtmux:outcome-value outcome)
      (is (eq t present-p))
      (is (equalp #(("retained")) value)))))

(defclass bad-close-client (libtmux:client) ())
(defmethod libtmux:close-client ((client bad-close-client))
  (call-next-method)
  (error "cleanup failed"))

(test resource-scope-values-and-exits
  (let ((original (make-instance 'libtmux:client))
        (replacement (make-instance 'libtmux:client)))
    (flet ((libtmux:open-client () original))
      (is (equal '(1 nil :tail)
                 (multiple-value-list
                  (libtmux:with-client (client)
                    (setf client replacement)
                    (is (eq replacement client))
                    (values 1 nil :tail))))))
    (is (not (libtmux:client-open-p original)))
    (is (libtmux:client-open-p replacement))
    (libtmux:close-client replacement))
  (let ((client (make-instance 'bad-close-client)))
    (flet ((libtmux:open-client () client))
      (is (eq :preserved
              (catch 'leave
                (libtmux:with-client (owned)
                  (declare (ignore owned))
                  (throw 'leave :preserved)))))
      (is (= 1 (length (libtmux:client-cleanup-failures client))))
      (signals simple-error
        (libtmux:with-client (owned) (declare (ignore owned)) :normal))))
  (let ((client (make-instance 'bad-close-client)))
    (flet ((libtmux:open-client () client))
      (is (equal "primary"
                 (handler-case
                     (libtmux:with-client (owned)
                       (declare (ignore owned)) (error "primary"))
                   (simple-error (condition) (princ-to-string condition)))))
      (is (= 1 (length (libtmux:client-cleanup-failures client)))))))

(test supported-version-floor
  (signals libtmux:unsupported-tmux (libtmux.internal::supported-version "3.3"))
  (signals libtmux:unsupported-tmux (libtmux.internal::supported-version "3.2a"))
  (signals libtmux:unsupported-tmux (libtmux.internal::supported-version "next-3.8"))
  (dolist (version '("3.3a" "3.4" "3.5" "3.5a" "3.6" "3.6a" "3.6b"
                     "3.7" "3.7a" "3.7b" "3.7c" "3.8"))
    (is (equal version (libtmux.internal::supported-version version)))))

(test cancellation-without-resource-allocation
  (let ((token (libtmux:make-cancellation-token)))
    (is (not (libtmux:cancelled-p token)))
    (is (libtmux:cancel token))
    (is (not (libtmux:cancel token)))
    (is (libtmux:cancelled-p token))
    (is (null (slot-value token 'libtmux::registrations)))))

(test finite-argument-validation
  (let ((cycle (list "arg")))
    (setf (cdr cycle) cycle)
    (signals libtmux:invalid-argument (libtmux.internal::argument-vector cycle)))
  (signals libtmux:invalid-argument (libtmux.internal::argument-vector '("a" . "b")))
  (signals libtmux:invalid-argument (libtmux.internal::argument-vector '("a" 1)))
  (signals libtmux:invalid-argument (libtmux.internal::octet-vector #(0 256)))
  (signals libtmux:invalid-argument (libtmux.internal::check-limits -1 100)))

(test custom-layout-headers-fail-before-dispatch
  (let ((libtmux.internal::*process-launched-hook*
          (lambda (job) (declare (ignore job)) (error "Layout validation contacted tmux"))))
    (dolist (text '("not-a-layout" "" "FFFF" "FFFF," "FFF,80x24,0,0,0" " FFFF,80x24,0,0,0"))
      (signals libtmux:invalid-argument (libtmux.internal::layout-argument (list :custom text))))
    (is (string= "0000,80x24,0,0,0"
                 (libtmux.internal::layout-argument '(:custom "0000,80x24,0,0,0"))))
    (multiple-value-bind (text json-p) (libtmux.internal::layout-argument '(:custom "{\"V\":2,\"L\":{}}"))
      (is (string= "{\"V\":2,\"L\":{}}" text))
      (is-true json-p))
    (let* ((source (copy-seq "0000,80x24,0,0,0"))
           (argument (libtmux.internal::layout-argument (list :custom source))))
      (setf (char source 0) #\F)
      (is (char= #\0 (char argument 0))))
    (let ((json (concatenate 'string (string #\Newline) " {\"V\":2,\"L\":{}}")))
      (is (string= json (libtmux.internal::layout-argument (list :custom json)))))))

(test wait-channel-validation-precedes-io
  (let ((calls 0))
    (let ((libtmux.internal::*process-started-hook*
            (lambda (process) (declare (ignore process)) (incf calls))))
      (signals libtmux:invalid-argument (libtmux:wait-for nil ""))
      (signals libtmux:invalid-argument (libtmux:wait-for nil (string #\Null)))
      (signals libtmux:invalid-argument (libtmux:wait-for nil 7))
      (signals libtmux:invalid-argument (libtmux:wait-for nil "channel" :operation :unknown))
      (is (zerop calls)))))

(test display-message-validation-precedes-io
  (let ((calls 0))
    (let ((libtmux.internal::*process-started-hook*
            (lambda (process) (declare (ignore process)) (incf calls))))
      (signals libtmux:invalid-argument (libtmux:display-message nil 7))
      (signals libtmux:invalid-argument (libtmux:display-message nil (string #\Null)))
      (signals libtmux:invalid-argument (libtmux:display-message nil "text" :target "@0"))
      (signals libtmux:invalid-argument
        (libtmux:display-message nil "text" :target (make-instance 'libtmux:attached-client)))
      (is (zerop calls)))))

(test key-command-validation-precedes-io
  (let ((calls 0))
    (let ((libtmux.internal::*process-started-hook*
            (lambda (process) (declare (ignore process)) (incf calls))))
      (signals libtmux:invalid-argument (libtmux:bind-key nil "x"))
      (signals libtmux:invalid-argument
        (libtmux:bind-key nil "x" :command '("list-sessions") :command-source "list-sessions"))
      (signals libtmux:invalid-argument
        (libtmux:bind-key nil "x" :command '("LIBTMUX_BIND=not-an-inert-command")))
      (signals libtmux:invalid-argument
        (libtmux:bind-key nil "x" :command-source (string #\Null)))
      (signals libtmux:invalid-argument (libtmux:list-commands nil :format 7))
      (signals libtmux:invalid-argument (libtmux:list-keys nil :key (string #\Null)))
      (signals libtmux:invalid-argument (libtmux:unbind-key nil "x" :table ""))
      (is (zerop calls)))))

(test server-access-validation-precedes-io
  (let ((calls 0))
    (let ((libtmux.internal::*process-started-hook*
            (lambda (process) (declare (ignore process)) (incf calls))))
      (signals libtmux:invalid-argument (libtmux:server-access nil 7 :allow))
      (signals libtmux:invalid-argument (libtmux:server-access nil "" :allow))
      (signals libtmux:invalid-argument (libtmux:server-access nil (string #\Null) :allow))
      (signals libtmux:invalid-argument (libtmux:server-access nil "principal" :unknown))
      (is (zerop calls)))))

(test lock-session-rejects-invalid-targets-and-command-overrides
  (let ((calls 0))
    (let ((libtmux.internal::*process-started-hook*
            (lambda (process) (declare (ignore process)) (incf calls))))
      (signals libtmux:invalid-argument (libtmux:lock-session nil nil))
      (signals libtmux:unsupported-configuration
        (libtmux.internal::check-command-aliases "lock-session=kill-server" nil))
      (is (zerop calls)))))

(test unsupported-host-fails-before-program-resolution
  (dolist (feature '(:sbcl :linux :x86-64))
    (let ((*features* (remove feature *features*)))
      (let ((condition
              (handler-case
                  (libtmux:open-client :program "libtmux-deliberately-absent-program")
                (libtmux:libtmux-error (condition) condition))))
        (is (typep condition 'libtmux:unsupported-platform))
        (when (typep condition 'libtmux:unsupported-platform)
          (is (eq :runtime-profile (libtmux:error-feature condition)))
          (is (search "SBCL on Linux x86-64" (libtmux:error-message condition))))))))

(test script-program-error-identifies-selected-path
  (let* ((path (namestring (asdf:system-relative-pathname "libtmux" "tools/lisp.sh")))
         (condition (handler-case (libtmux.internal::native-program path)
                      (libtmux:invalid-argument (condition) condition))))
    (is (typep condition 'libtmux:invalid-argument))
    (is (search path (libtmux:error-message condition)))
    (is (search ":PROGRAM" (libtmux:error-message condition)))))

(test platform-probe-failure-retains-cause-before-program-resolution
  (let ((original (symbol-function 'libtmux.internal::ensure-process-platform))
        (cause (make-condition 'simple-error :format-control "missing libc symbol")))
    (unwind-protect
         (progn
           (setf (symbol-function 'libtmux.internal::ensure-process-platform)
                 (lambda ()
                   (libtmux.internal::probe-platform-facility
                    :pidfd "libc pidfd_open is required" (lambda () (error cause)))))
           (let ((condition
                   (handler-case
                       (libtmux:open-client :program "libtmux-deliberately-absent-program")
                     (libtmux:libtmux-error (condition) condition))))
             (is (typep condition 'libtmux:unsupported-platform))
             (is (eq :pidfd (libtmux:error-feature condition)))
             (is (eq cause (libtmux:error-cause condition)))
             (is (null (libtmux:error-client condition)))
             (is (null (libtmux:error-outcome condition)))))
      (setf (symbol-function 'libtmux.internal::ensure-process-platform) original))))
