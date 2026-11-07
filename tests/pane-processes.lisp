(in-package #:libtmux.tests)

(in-suite integration)

(test oversized-literal-pipe-command-fails-before-io
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((pane (aref (libtmux:fetch-panes client) 0)) (calls 0))
        (let ((libtmux.internal::*process-started-hook*
                (lambda (process) (declare (ignore process)) (incf calls))))
          (signals libtmux:invalid-argument
            (libtmux:pipe-pane client pane
                               :shell-command (concatenate 'string (make-string 8191 :initial-element #\a) "%")))
          (is (zerop calls)))))))

(test respawn-replaces-processes-and-preserves-captures
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((snapshot (libtmux:fetch-snapshot client))
             (pane (aref (libtmux:panes snapshot) 0))
             (window (aref (libtmux:windows snapshot) 0))
             (old-pid (libtmux:field-value pane :pane/pid)))
        (signals libtmux:command-failed
          (libtmux::respawn-pane client pane :command '("/bin/cat")))
        (let* ((outcome (libtmux::respawn-pane client pane :kill t :command '("/bin/cat")))
               (replacement (libtmux:outcome-value outcome)))
          (is (eq :succeeded (libtmux:outcome-status outcome)))
          (is (libtmux:same-entity-p pane replacement))
          (is (/= old-pid (libtmux:field-value replacement :pane/pid)))
          (is (= old-pid (libtmux:field-value pane :pane/pid))))
        (libtmux:split-pane client pane :command '("/bin/cat"))
        (let* ((before (libtmux:refresh client window))
               (outcome (libtmux::respawn-window client window :kill t :command '("/bin/cat")))
               (after (libtmux:outcome-value outcome)))
          (is (= 2 (length (libtmux:panes before))))
          (is (= 1 (length (libtmux:panes after))))
          (is (libtmux:same-entity-p window after))
          (is (= 1 (length (libtmux:panes window)))))))))

(test pane-pipe-preserves-literal-shell-and-uses-consumption-barrier
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((session (aref (libtmux:fetch-sessions client) 0))
             (binary (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux"))
             (path (namestring (merge-pathnames "%Y-#{pane_id} result" (fixture-directory fixture))))
             (payload "pane output λ")
             (literal "%Y #{pane_id} λ;")
             (window (libtmux:outcome-value
                      (libtmux:new-window
                       client session
                       :command (list "/usr/bin/python3" "-c"
                                      "import os,subprocess,sys,tty
tty.setraw(0)
subprocess.run([sys.argv[1], '-N', '-S', sys.argv[2], 'wait-for', '-S', 'pane-pipe-ready'], check=True)
os.read(0,1)
os.write(1,sys.argv[3].encode())
os.read(0,1)
" binary (fixture-socket fixture) payload))))
             (pane (aref (libtmux:panes window) 0))
             (program "import subprocess,sys
subprocess.run([sys.argv[2], '-N', '-S', sys.argv[3], 'wait-for', '-S', 'pipe-reader-ready'], check=True)
data=sys.stdin.buffer.read(int(sys.argv[4]))
with open(sys.argv[1], 'wb') as stream:
    stream.write(data+sys.argv[5].encode())
subprocess.run([sys.argv[2], '-N', '-S', sys.argv[3], 'wait-for', '-S', 'pipe-reader-consumed'], check=True)
")
             (shell (format nil "~{~A~^ ~}"
                            (mapcar #'uiop:escape-sh-token
                                    (list "/usr/bin/python3" "-c" program path binary
                                          (fixture-socket fixture)
                                          (write-to-string (length (libtmux.internal::encode-utf8 payload)))
                                          literal)))))
        (libtmux:run-command client '("wait-for" "pane-pipe-ready") :effect :read :timeout 0.5)
        (is (eq :succeeded (libtmux:outcome-status
                           (libtmux::pipe-pane client pane :shell-command shell))))
        (libtmux:run-command client '("wait-for" "pipe-reader-ready") :effect :read :timeout 0.5)
        (libtmux:send-text client pane "g")
        (libtmux:run-command client '("wait-for" "pipe-reader-consumed") :effect :read :timeout 0.5)
        (is (equalp (libtmux.internal::encode-utf8 (concatenate 'string payload literal))
                    (read-file-octets path)))
        (is (eq :succeeded (libtmux:outcome-status (libtmux::pipe-pane client pane))))
        (is (equal (format nil "0~%")
                   (fixture-ok fixture "display-message" "-p" "-t" (libtmux:id pane) "#{pane_pipe}")))))))
