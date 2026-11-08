(require :asdf)

(asdf:load-asd (truename (merge-pathnames "../libtmux.asd" *load-truename*)))
(asdf:load-system "libtmux")

;;; docs:managed
(defun inspect-owned-workspace (&key (program "tmux"))
  "Start an isolated daemon; return owned pane data after closing both resources."
  (libtmux:with-daemon (daemon :program program)
    (libtmux:with-client (client :program (libtmux:daemon-program daemon)
                                 :socket-path (libtmux:daemon-socket-path daemon))
      (let ((outcome (libtmux:new-session client :name "demo" :command '("/bin/cat"))))
        (when (libtmux:outcome-observation-error outcome)
          (error (libtmux:outcome-observation-error outcome))))
      (map 'list #'libtmux:entity-data
           (libtmux:panes (libtmux:fetch-snapshot client))))))
;;; docs:end

(let ((panes (inspect-owned-workspace :program (or (uiop:getenv "LIBTMUX_PROGRAM") "tmux"))))
  (assert (= 1 (length panes)))
  (assert (getf (first panes) :pane/active))
  (assert (stringp (getf (first panes) :pane/id)))
  (assert (zerop (length (libtmux:pending-daemon-cleanups))))
  (format t "MANAGED DAEMON PASS: ~S~%" panes))
