(require :asdf)

(defparameter *arguments* (uiop:command-line-arguments))
(assert (= 3 (length *arguments*)))

(defparameter *source-root* (first *arguments*))
(defparameter *program* (second *arguments*))
(defparameter *socket-path* (third *arguments*))

(asdf:load-asd
 (truename (merge-pathnames "libtmux.asd"
                            (uiop:ensure-directory-pathname *source-root*))))
(asdf:load-system "libtmux")

(defun observed-value (outcome)
  "Return OUTCOME's observed value, or signal its observation failure."
  (when (libtmux:outcome-observation-error outcome)
    (error (libtmux:outcome-observation-error outcome)))
  (multiple-value-bind (value present-p) (libtmux:outcome-value outcome)
    (unless present-p
      (error "The operation did not return an observation"))
    value))

(libtmux:with-client (client :program *program* :socket-path *socket-path*
                               :config-file "/dev/null")
    (let ((normal nil))
      (unwind-protect
           (multiple-value-prog1
               (let* ((before (libtmux:fetch-snapshot client))
                      (demo (find "demo" (libtmux:sessions before)
                                  :key #'libtmux:name :test #'string=))
                      (editor-link (aref (libtmux:window-links demo) 0))
                      (editor (libtmux:window editor-link))
                      (left (aref (libtmux:panes editor) 0))
                      (right (observed-value
                              (libtmux:split-pane
                               client left :direction :horizontal
                               :command '("/bin/cat"))))
                      (logs (observed-value
                             (libtmux:new-window
                              client demo :name "logs"
                              :command '("/bin/cat")))))
                 (declare (ignore logs))
                 (libtmux:send-text client right "hello from tmux" :enter t)
                 (multiple-value-bind (text outcome)
                     (libtmux:capture-pane client right)
                   (assert (eq :succeeded (libtmux:outcome-status outcome)))
                   (assert (search "hello from tmux" text)))
                 (let* ((snapshot (libtmux:fetch-snapshot client))
                        (pane (find (libtmux:id right)
                                    (libtmux:panes snapshot)
                                    :key #'libtmux:id :test #'string=))
                        (window (libtmux:window pane))
                        (owner-link (aref (libtmux:window-links window) 0))
                        (owner (libtmux:session owner-link)))
                   (loop for session across (libtmux:sessions snapshot)
                         do (format t "session ~A~%" (libtmux:name session))
                            (loop for link across
                                    (libtmux:window-links session)
                                  for each = (libtmux:window link)
                                  do (format t "  window ~D:~A:"
                                             (libtmux:index link)
                                             (libtmux:name each))
                                     (loop for item across
                                             (libtmux:panes each)
                                           do (format t " ~A"
                                                      (libtmux:id item)))
                                     (terpri)))
                   (format t "~A is in window ~A of session ~A~%"
                           (libtmux:id pane) (libtmux:name window)
                           (libtmux:name owner))))
             (setf normal t))
        (handler-case (libtmux:kill-server client)
          (error (condition)
            (if normal
                (error condition)
                (warn "Owned server cleanup also failed: ~A" condition)))))))
