(require :asdf)
(asdf:load-asd (truename (merge-pathnames "../libtmux.asd" *load-truename*)))
(asdf:load-system "libtmux/control")

(defpackage #:libtmux.control.example
  (:use #:cl)
  (:local-nicknames (#:tm #:libtmux) (#:control #:libtmux.control)))
(in-package #:libtmux.control.example)

;;; docs:control
(defun echo-through-control (client session pane)
  "Send literal text and collect pane-output bytes on one scoped connection."
  (control:with-connection (connection client session)
    (let ((write (control:submit-command
                  connection (list "send-keys" "-t" (tm:id pane) "-l" "hello from control")
                  :effect :mutation))
          (enter (control:submit-command
                  connection (list "send-keys" "-t" (tm:id pane) "Enter")
                  :effect :mutation)))
      (dolist (request (list write enter))
        (multiple-value-bind (result delivery) (control:await-request request :timeout 1)
          (assert (eq :ready delivery))
          (assert (eq :completed (getf result :status))))))
    (let ((bytes (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0))
          (expected (map 'vector #'char-code "hello from control"))
          (deadline (+ (get-internal-real-time) internal-time-units-per-second)))
      (loop repeat 64
            until (search expected bytes)
            for remaining = (/ (- deadline (get-internal-real-time)) internal-time-units-per-second)
            do (assert (plusp remaining))
               (multiple-value-bind (event delivery) (control:next-event connection :timeout remaining)
                 (assert (eq :ready delivery))
                 (case (getf event :kind)
                   (:output
                    (assert (string= (tm:id pane) (getf event :pane)))
                    (loop for byte across (getf event :data) do (vector-push-extend byte bytes)))
                   ((:gap :end) (error "Output stream ended or lost data: ~S" event)))))
      (assert (search expected bytes))
      (coerce bytes '(simple-array (unsigned-byte 8) (*))))))
;;; docs:end

(let ((program (or (uiop:getenv "LIBTMUX_PROGRAM") "tmux")))
  (tm:with-daemon (daemon :program program)
    (tm:with-client (client :program (tm:daemon-program daemon)
                             :socket-path (tm:daemon-socket-path daemon))
      (let ((outcome (tm:new-session client :name "control-demo" :command '("/bin/cat"))))
        (assert (eq :succeeded (tm:outcome-status outcome)))
        (when (tm:outcome-observation-error outcome) (error (tm:outcome-observation-error outcome))))
      (let* ((snapshot (tm:fetch-snapshot client))
             (bytes (echo-through-control client (aref (tm:sessions snapshot) 0)
                                          (aref (tm:panes snapshot) 0))))
        (assert (plusp (length bytes)))
        (assert (= 1 (length (tm:fetch-sessions client))))
        (format t "CONTROL PASS: queued writes, streamed ~D bytes; daemon survived connection close~%"
                (length bytes)))))
  (assert (zerop (length (control:pending-cleanups))))
  (assert (zerop (length (tm:pending-daemon-cleanups)))))
