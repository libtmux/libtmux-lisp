;;; An example application: signal readiness, consume one request line, write a
;;; receipt file, then signal that the request was consumed.
;;;
;;;   sbcl --script examples/worker.lisp PROGRAM SOCKET READY [CONSUMED RECEIPT]
;;;
;;; PROGRAM and SOCKET select the tmux daemon; READY and CONSUMED name wait
;;; channels. Without CONSUMED and RECEIPT the worker only signals READY. The
;;; tutorial and the owned-workspace example start it in a pane.

(load (merge-pathnames "../tools/load.lisp" *load-truename*))
(asdf:load-system "libtmux")

(destructuring-bind (program socket ready &optional consumed receipt)
    (uiop:command-line-arguments)
  (libtmux:with-client (client :program program :socket-path socket)
    (libtmux:wait-for client ready :operation :signal)
    (when consumed
      (let ((message (read-line)))
        (with-open-file (stream receipt :direction :output :if-exists :supersede
                                        :external-format :utf-8)
          (write-string message stream))
        (format t "processed: ~A~%" message)
        (finish-output)
        (libtmux:wait-for client consumed :operation :signal))))
  ;; Keep the pane open, as the application would, until the daemon stops.
  (loop while (read-char *standard-input* nil nil)))
