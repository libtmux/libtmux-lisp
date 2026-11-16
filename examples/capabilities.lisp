(load (merge-pathnames "../tools/load.lisp" *load-truename*))
;;; docs:capabilities
(asdf:load-system "libtmux/control")

(defun inspect-capabilities (&key (program "tmux"))
  "Return a daemon report; use queued discovery when the daemon supports control."
  (libtmux:with-daemon (daemon :program program)
    (libtmux:with-client (client :program (libtmux:daemon-program daemon)
                                 :socket-path (libtmux:daemon-socket-path daemon))
      (let ((report (libtmux:capabilities client)))
        (when (libtmux:supports-p report :control)
          (let ((outcome (libtmux:new-session client :name "capabilities" :command '("/bin/cat"))))
            (when (libtmux:outcome-observation-error outcome)
              (error (libtmux:outcome-observation-error outcome))))
          (let ((session (aref (libtmux:fetch-sessions client) 0)))
            (libtmux.control:with-connection (connection client session)
              (let ((request (libtmux.control:submit-capabilities connection)))
                (multiple-value-bind (current delivery result)
                    (libtmux.control:await-capabilities request :timeout 1)
                  (unless (and (eq :ready delivery) current)
                    (error "Capability request did not complete: ~S ~S" delivery result))
                  (assert (equal (libtmux:capability-provenance report)
                                 (libtmux:capability-provenance current))))))))
        report))))
;;; docs:end

(let ((report (inspect-capabilities :program (or (uiop:getenv "LIBTMUX_PROGRAM") "tmux"))))
  (assert (= 11 (length (libtmux:capability-features report))))
  (assert (plusp (getf (libtmux:capability-provenance report) :server/pid)))
  (assert (zerop (length (libtmux:pending-daemon-cleanups))))
  (assert (zerop (length (libtmux.control:pending-cleanups))))
  (format t "CAPABILITIES PASS: tmux ~A; control ~A; resources closed~%"
          (libtmux:capability-version report) (libtmux:supports-p report :control)))
