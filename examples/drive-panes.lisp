(load (merge-pathnames "../tools/load.lisp" *load-truename*))

;;; docs:panes
(asdf:load-system "libtmux")

(defun drive-panes (&key (program "tmux"))
  "Split a pane, send it text, capture its screen and resize; return what tmux reports."
  (libtmux:with-daemon (daemon :program program)
    (libtmux:with-client (client :program (libtmux:daemon-program daemon)
                                 :socket-path (libtmux:daemon-socket-path daemon))
      (flet ((observed (outcome)
               (when (libtmux:outcome-observation-error outcome)
                 (error (libtmux:outcome-observation-error outcome)))
               (values (libtmux:outcome-value outcome))))
        (observed (libtmux:new-session client :name "demo" :command '("/bin/cat")))
        (let* ((left (aref (libtmux:fetch-panes client) 0))
               (right (observed (libtmux:split-pane client left :direction :horizontal
                                                                :command '("/bin/cat")))))
          (libtmux:send-text client right "hello from Lisp" :enter t)
          (let* ((text (libtmux:capture-pane client right))
                 (window (observed (libtmux:resize-window client (libtmux:window right)
                                                          :width 100 :height 30)))
                 (narrow (observed (libtmux:resize-pane client right :width 20))))
            (list :text (string-right-trim '(#\Newline) text)
                  :window-size (list (libtmux:width window) (libtmux:height window))
                  :pane-width (libtmux:width narrow))))))))
;;; docs:end

(let ((results (drive-panes)))
  (assert (search "hello from Lisp" (getf results :text)))
  (assert (equal '(100 30) (getf results :window-size)))
  (assert (= 20 (getf results :pane-width)))
  (assert (zerop (length (libtmux:pending-daemon-cleanups))))
  (format t "PANE OPERATIONS PASS: ~S~%" results))
