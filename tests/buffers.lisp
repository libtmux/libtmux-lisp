(in-package #:libtmux.tests)

(in-suite integration)

(defun read-file-octets (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      bytes)))

(test buffer-creation-rejects-rewritten-names-before-io
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((calls 0))
        (let ((libtmux.internal::*process-started-hook*
                (lambda (process) (declare (ignore process)) (incf calls))))
          (signals libtmux:invalid-argument (libtmux:set-buffer client "text" :name "back\\slash"))
          (signals libtmux:invalid-argument
            (libtmux:load-buffer client "/missing-buffer-file" :name (format nil "line~%break")))
          (is (zerop calls)))))))

(test buffer-read-rejects-recovered-errors-and-refusal-aliases
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (when (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8")
        (fixture-ok fixture "set-hook" "-g" "command-error" "run-shell 'printf spoof'"))
      (handler-case
          (progn (libtmux:show-buffer client :name "missing")
                 (fail "A recovered error became a successful byte read"))
        (libtmux:command-failed (condition)
          (let ((outcome (libtmux:error-outcome condition)))
            (is (eq :failed (libtmux:outcome-status outcome)))
            (is (plusp (length (libtmux:outcome-stderr outcome)))))))
      (fixture-ok fixture "set-option" "-s" "command-alias[100]"
                  "libtmux-internal-read-server-refused=list-sessions")
      (handler-case
          (progn (libtmux:show-buffer client :name "missing")
                 (fail "A reserved refusal alias was accepted"))
        (libtmux:unsupported-configuration (condition)
          (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition)))))))))

(test buffer-read-guards-foreign-daemon-without-parsing-payload
  (with-tmux-fixture (first)
    (with-tmux-fixture (second)
      (with-fixture-client (client first)
        (libtmux:set-buffer client "original" :name "payload")
        (fixture-ok second "set-buffer" "-b" "payload" "foreign")
        (when (libtmux.internal::version-at-least-p (libtmux:tmux-version client) "3.8")
          (fixture-ok second "set-hook" "-g" "command-error" "run-shell 'printf spoof'"))
        (let* ((selected (fixture-socket first))
               (backup (concatenate 'string selected "-saved"))
               (changed nil))
          (unwind-protect
               (let ((libtmux.internal::*before-dispatch-hook*
                       (lambda (job)
                         (when (and (not changed)
                                    (find "if-shell" (libtmux.internal::process-job-argv job) :test #'equal))
                           (sb-posix:rename selected backup)
                           (sb-posix:symlink (fixture-socket second) selected)
                           (setf changed t)))))
                 (handler-case
                     (progn (libtmux:show-buffer client :name "payload")
                            (fail "A foreign daemon supplied buffer bytes"))
                   (libtmux:command-failed (condition)
                     (is (eq :failed (libtmux:outcome-status (libtmux:error-outcome condition))))
                     (is (plusp (length (libtmux:outcome-stderr (libtmux:error-outcome condition))))))))
            (when changed
              (sb-posix:unlink selected)
              (sb-posix:rename backup selected)))
          (is (eq t changed)))
        (let ((data (libtmux.internal::encode-utf8
                     (format nil "unknown command: libtmux-internal-read-server-refused~%libtmux-entered:complete~%"))))
          (libtmux:set-buffer client data :name "payload")
          (is (equalp data (libtmux:show-buffer client :name "payload"))))))))

(test buffer-bytes-files-and-missing-name-safety
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((name "buffer-#{pid},%λ;")
             (data #(0 255 128 10 13 9 35 123 125 37 206 187))
             (path (concatenate 'string (namestring (fixture-directory fixture))
                                (format nil "~A~C~C" name #\Newline #\Tab)))
             (empty (merge-pathnames "empty" (fixture-directory fixture)))
             (actual (libtmux:tmux-version client)))
        (libtmux:set-buffer client data :name name)
        (multiple-value-bind (bytes outcome) (libtmux:show-buffer client :name name)
          (is (equalp data bytes))
          (setf (aref bytes 0) 41)
          (is (equalp data (libtmux:outcome-stdout outcome))))
        (let ((row (aref (libtmux:list-buffers client) 0)))
          (is (string= name (getf row :buffer/name)))
          (is (= (length data) (getf row :buffer/size)))
          (is (integerp (getf row :buffer/created))))
        (libtmux:save-buffer client path :name name)
        (is (equalp data (read-file-octets path)))
        (libtmux:set-buffer client "replacement" :name name)
        (libtmux:load-buffer client path :name name)
        (is (equalp data (libtmux:show-buffer client :name name)))
        (libtmux:set-buffer client #() :name name)
        (libtmux:set-buffer client "" :name name)
        (with-open-file (stream empty :direction :output :element-type '(unsigned-byte 8))
          (declare (ignore stream)))
        (libtmux:load-buffer client (namestring empty) :name name)
        (is (equalp data (libtmux:show-buffer client :name name)))
        (libtmux:set-buffer client "λ" :name name :append t)
        (is (equalp (concatenate 'vector data #(206 187)) (libtmux:show-buffer client :name name)))
        (unwind-protect
             (if (libtmux.internal::version-at-least-p actual "3.4")
                 (progn
                   (setf (slot-value client 'libtmux::version) "3.3a")
                   (signals libtmux:command-failed (libtmux:delete-buffer client :name "absent-buffer")))
                 (progn
                   (setf (slot-value client 'libtmux::version) "9.0")
                   (handler-case (progn (libtmux:delete-buffer client :name "absent-buffer")
                                        (fail "Unsafe named deletion was dispatched"))
                     (libtmux:unsupported-capability (condition)
                       (is (eq :named-buffer-deletion (libtmux:error-feature condition)))
                       (is (string= actual (libtmux:error-actual-version condition)))
                       (is (eq :not-dispatched (libtmux:outcome-status (libtmux:error-outcome condition))))))))
          (setf (slot-value client 'libtmux::version) actual))
        (is (= 1 (length (libtmux:list-buffers client))))
        (libtmux:set-buffer client "automatic")
        (libtmux:delete-buffer client)
        (is (= 1 (length (libtmux:list-buffers client))))
        (is (string= name (getf (aref (libtmux:list-buffers client) 0) :buffer/name)))))))

(test paste-preserves-bytes-and-signals-application-consumption
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((session (aref (libtmux:fetch-sessions client) 0))
             (path (namestring (merge-pathnames "paste-result" (fixture-directory fixture))))
             (data #(0 255 13 10 9 206 187))
             (window (libtmux:outcome-value
                      (libtmux:new-window
                       client session
                       :command (list "/usr/bin/python3" "-c"
                                      "import os,subprocess,sys,tty
tty.setraw(0)
def signal(name):
    subprocess.run([sys.argv[2], '-N', '-S', sys.argv[3], 'wait-for', '-S', name], check=True)
signal('paste-ready')
data = b''
while len(data) < int(sys.argv[4]):
    data += os.read(0, int(sys.argv[4]) - len(data))
with open(sys.argv[1], 'wb') as stream:
    stream.write(data)
signal('paste-consumed')
os.read(0, 1)
" path (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                      (fixture-socket fixture) (write-to-string (length data))))))
             (pane (aref (libtmux:panes window) 0)))
        (libtmux:run-command client '("wait-for" "paste-ready") :effect :read :timeout 0.5)
        (libtmux:set-buffer client data :name "payload")
        (is (eq :succeeded (libtmux:outcome-status
                           (libtmux:paste-buffer client pane :name "payload" :verbatim t :delete t))))
        (libtmux:run-command client '("wait-for" "paste-consumed") :effect :read :timeout 0.5)
        (is (equalp data (read-file-octets path)))
        (is (zerop (length (libtmux:list-buffers client))))))))
