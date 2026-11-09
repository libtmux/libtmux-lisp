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

;;; docs:controlnotifications
(defun observe-window-rename (client session window)
  "Rename explicitly and return its owned notification bytes."
  (let ((captured-name (tm:name window))
        (expected (map 'vector #'char-code
                       (format nil "%window-renamed ~A event-editors" (tm:id window)))))
    (control:with-connection (connection client session)
      (let ((outcome (tm:rename-window client window "event-editors" :observe nil)))
        (assert (eq :succeeded (tm:outcome-status outcome))))
      (let ((deadline (+ (get-internal-real-time) internal-time-units-per-second)))
        (loop for remaining = (/ (- deadline (get-internal-real-time)) internal-time-units-per-second)
              do (assert (plusp remaining))
                 (multiple-value-bind (event delivery) (control:next-event connection :timeout remaining)
                   (assert (eq :ready delivery))
                   (when (member (getf event :kind) '(:gap :end))
                     (error "Notification stream ended or lost data: ~S" event))
                   (when (and (eq :notification (getf event :kind))
                              (equalp expected (getf event :data)))
                     (assert (string= captured-name (tm:name window)))
                     (return (getf event :data)))))))))
;;; docs:end

;;; docs:controlreconnect
(defun inspect-after-reconnect (client session)
  "Return owned pane data and provenance after an explicit generation change."
  (let ((before (getf (tm:provenance session) :generation)))
    (control:with-connection (old client session)
      (control:with-reconnection (connection snapshot old)
        (assert (eq :closed (control:connection-state old)))
        (assert (> (getf (tm:provenance snapshot) :generation) before))
        (let ((request (control:submit-command
                        connection '("display-message" "-p" "-l" "reconnected") :effect :read)))
          (multiple-value-bind (result delivery) (control:await-request request :timeout 1)
            (assert (eq :ready delivery))
            (assert (eq :completed (getf result :status)))))
        (values (map 'vector #'tm:entity-data (tm:panes snapshot))
                (tm:provenance snapshot))))))
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
                (length bytes))
        (let ((notification (observe-window-rename client (aref (tm:sessions snapshot) 0)
                                                   (aref (tm:windows snapshot) 0))))
          (assert (plusp (length notification)))
          (format t "CONTROL NOTIFICATION PASS: explicit rename observed; captured name unchanged~%"))
        (multiple-value-bind (data provenance)
            (inspect-after-reconnect client (aref (tm:sessions snapshot) 0))
          (assert (= 1 (length data)))
          (assert (stringp (getf (aref data 0) :pane/id)))
          (format t "CONTROL RECONNECT PASS: generation ~D; owned pane data remains after scope exit~%"
                  (getf provenance :generation))))))
  (assert (zerop (length (control:pending-cleanups))))
  (assert (zerop (length (tm:pending-daemon-cleanups)))))
