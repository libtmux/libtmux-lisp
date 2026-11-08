(in-package #:libtmux.tests)

(in-suite integration)

(test native-creation-argv-and-owned-results
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((directory (concatenate 'string (namestring (fixture-directory fixture))
                                    "cwd-#[one]##[#{pid}]/"))
             (script (concatenate 'string directory "one executable;$'λ.py"))
             (result (concatenate 'string directory "argv-result"))
             (program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux"))
             (environment `(("LIBTMUX_RESULT" . ,result)
                            ("LIBTMUX_PROGRAM" . ,program)
                            ("LIBTMUX_SOCKET" . ,(fixture-socket fixture))
                            ("LIBTMUX_VALUE" . "λ$`'\\")))
             (payload '("" "space here" ";" "$HOME`x`" "\\" "λ")))
        (sb-posix:mkdir (sb-ext:parse-native-namestring directory) #o700)
        (with-open-file (stream (sb-ext:parse-native-namestring script) :direction :output :if-exists :error)
          (write-string "#!/usr/bin/python3
import os, subprocess, sys
parts = [os.getcwd(), os.environ['LIBTMUX_VALUE'], *sys.argv[1:]]
with open(os.environ['LIBTMUX_RESULT'], 'wb') as stream:
    stream.write(bytes([0]).join(part.encode('utf-8') for part in parts))
subprocess.run([os.environ['LIBTMUX_PROGRAM'], '-N', '-S', os.environ['LIBTMUX_SOCKET'], 'wait-for', '-S', 'creation-ready'], check=True)
sys.stdin.buffer.read(1)
" stream))
        (sb-posix:chmod (sb-ext:parse-native-namestring script) #o700)
        (let* ((outcome (libtmux:new-session client :name "created-#{pid}" :command (list script)
                                                    :cwd directory :environment environment))
               (session (libtmux:outcome-value outcome)))
          (is (eq :succeeded (libtmux:outcome-status outcome)))
          (is (typep session 'libtmux:session))
          (is (equal "created-#{pid}" (libtmux:name session)))
          (libtmux:run-command client '("wait-for" "creation-ready") :effect :read :timeout 0.5)
          (is (equal (concatenate 'string (string-right-trim "/" directory)
                                  (string #\Null) (cdr (assoc "LIBTMUX_VALUE" environment :test #'equal)))
                     (uiop:read-file-string (sb-ext:parse-native-namestring result))))
          (let* ((outcome (libtmux:new-window client session :name "native-#{pid};" :index 4
                                             :cwd directory :environment environment
                                             :command (cons script payload)))
                 (window (libtmux:outcome-value outcome)))
            (is (typep window 'libtmux:window))
            (is (equal "native-#{pid};" (libtmux:name window)))
            (is (= 4 (libtmux:index (aref (libtmux:window-links window) 0))))
            (libtmux:run-command client '("wait-for" "creation-ready") :effect :read :timeout 0.5)
            (is (equal
                 (with-output-to-string (stream)
                   (loop for part in (append (list (string-right-trim "/" directory)
                                                  (cdr (assoc "LIBTMUX_VALUE" environment :test #'equal))) payload)
                         for first = t then nil
                         do (unless first (write-char #\Null stream)) (write-string part stream)))
                 (uiop:read-file-string (sb-ext:parse-native-namestring result))))
            (let ((pane (libtmux:outcome-value
                         (libtmux:split-pane client (aref (libtmux:panes window) 0)
                                            :direction :horizontal :percent 40 :command '("/bin/cat")))))
              (is (typep pane 'libtmux:pane))
              (is (= 2 (length (libtmux:panes (libtmux:window pane))))))))))))

(test creation-input-and-encoded-envelope-bounds
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((session (aref (libtmux:fetch-sessions client) 0)) (calls 0))
        (let ((libtmux.internal::*process-started-hook*
                (lambda (process) (declare (ignore process)) (incf calls))))
          (signals libtmux:invalid-argument (libtmux:new-window client session :command nil))
          (signals libtmux:invalid-argument
            (libtmux:new-window client session :command '("/bin/cat") :shell-command "cat"))
          (signals libtmux:invalid-argument (libtmux:new-window client session :shell-command nil))
          (is (zerop calls)))
        (handler-case
            (progn (libtmux:new-window client session :name (make-string 5000 :initial-element #\\))
                   (fail "Oversized encoded command was dispatched"))
          (libtmux:invalid-argument (condition)
            (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))))
        (is (= 1 (length (libtmux:fetch-windows client))))))))

(test literal-input-and-keys-use-application-readiness
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((session (aref (libtmux:fetch-sessions client) 0))
             (window (libtmux:outcome-value
                      (libtmux:new-window
                       client session
                       :command (list "/bin/sh" "-c"
                                      "cat; \"$1\" -N -S \"$2\" wait-for -S input-drained; exec cat"
                                      "input-test" (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                      (fixture-socket fixture)))))
             (pane (aref (libtmux:panes window) 0))
             (text "C-c literal #{pid}; λ$`"))
        (is (eq :succeeded (libtmux:outcome-status (libtmux:send-text client pane text :enter t))))
        (is (eq :succeeded (libtmux:outcome-status (libtmux:send-keys client pane '("C-d")))))
        (libtmux:run-command client '("wait-for" "input-drained") :effect :read :timeout 0.5)
        (is (not (null (search text (libtmux:capture-pane client pane)))))
        (is (eq :succeeded (libtmux:outcome-status (libtmux:copy-mode client pane))))
        (is (eq :succeeded (libtmux:outcome-status (libtmux:copy-mode client pane :exit t))))
        (is (eq :succeeded (libtmux:outcome-status (libtmux:clear-history client pane))))))))
