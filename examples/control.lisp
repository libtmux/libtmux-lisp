(load (merge-pathnames "../tools/load.lisp" *load-truename*))
;;; docs:controlsetup
(asdf:load-system "libtmux/control")

(defpackage #:libtmux.control.example
  (:use #:cl)
  (:local-nicknames (#:tm #:libtmux) (#:control #:libtmux.control)))
(in-package #:libtmux.control.example)
;;; docs:end

;;; docs:control
(defun echo-through-control (client session pane)
  "Send literal text and collect pane-output bytes on one scoped connection."
  (control:with-connection (connection client session)
    (let* ((id (tm:id pane))
           (text "hello from control")
           (write (control:submit-command
                   connection (list "send-keys" "-t" id "-l" text)
                   :effect :mutation))
           (enter (control:submit-command
                   connection (list "send-keys" "-t" id "Enter")
                   :effect :mutation)))
      (dolist (request (list write enter))
        (multiple-value-bind (result delivery)
            (control:await-request request :timeout 1)
          (assert (eq :ready delivery))
          (assert (eq :completed (getf result :status)))))
      (let ((bytes (make-array 0 :element-type '(unsigned-byte 8)
                                 :adjustable t :fill-pointer 0))
            (expected (map 'vector #'char-code text))
            (deadline (+ (get-internal-real-time)
                         internal-time-units-per-second)))
        (loop repeat 64
              until (search expected bytes)
              for left = (/ (- deadline (get-internal-real-time))
                            internal-time-units-per-second)
              do (assert (plusp left))
                 (multiple-value-bind (event delivery)
                     (control:next-event connection :timeout left)
                   (assert (eq :ready delivery))
                   (case (getf event :kind)
                     (:output
                      (assert (string= id (getf event :pane)))
                      (loop for byte across (getf event :data)
                            do (vector-push-extend byte bytes)))
                     ((:gap :end)
                      (error "Output stream ended or lost data: ~S" event)))))
        (assert (search expected bytes))
        (coerce bytes '(simple-array (unsigned-byte 8) (*)))))))
;;; docs:end

;;; docs:controlnotifications
(defun observe-window-rename (client session window)
  "Rename explicitly and return its owned notification bytes."
  (let* ((captured-name (tm:name window))
         (line (format nil "%window-renamed ~A event-editors" (tm:id window)))
         (expected (map 'vector #'char-code line)))
    (control:with-connection (connection client session)
      (let ((outcome (tm:rename-window client window "event-editors"
                                       :observe nil)))
        (assert (eq :succeeded (tm:outcome-status outcome))))
      (let ((deadline (+ (get-internal-real-time)
                         internal-time-units-per-second)))
        (loop for left = (/ (- deadline (get-internal-real-time))
                            internal-time-units-per-second)
              do (assert (plusp left))
                 (multiple-value-bind (event delivery)
                     (control:next-event connection :timeout left)
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
  (let ((before (getf (tm:provenance session) :generation))
        (query '("display-message" "-p" "-l" "reconnected")))
    (control:with-connection (old client session)
      (control:with-reconnection (connection snapshot old)
        (assert (eq :closed (control:connection-state old)))
        (assert (> (getf (tm:provenance snapshot) :generation) before))
        (let ((request (control:submit-command connection query :effect :read)))
          (multiple-value-bind (result delivery)
              (control:await-request request :timeout 1)
            (assert (eq :ready delivery))
            (assert (eq :completed (getf result :status)))))
        (values (map 'vector #'tm:entity-data (tm:panes snapshot))
                (tm:provenance snapshot))))))
;;; docs:end

(tm:with-daemon (daemon)
  (tm:with-client (client :program (tm:daemon-program daemon)
                          :socket-path (tm:daemon-socket-path daemon))
    (let* ((outcome (tm:new-session client :name "control-demo"
                                           :command '("/bin/cat")))
           (obs-error (tm:outcome-observation-error outcome)))
      (assert (eq :succeeded (tm:outcome-status outcome)))
      (when obs-error (error obs-error)))
    (let* ((snapshot (tm:fetch-snapshot client))
           (session (aref (tm:sessions snapshot) 0))
           (window (aref (tm:windows snapshot) 0))
           (pane (aref (tm:panes snapshot) 0))
           (bytes (echo-through-control client session pane)))
      (assert (plusp (length bytes)))
      (assert (= 1 (length (tm:fetch-sessions client))))
      (format t "CONTROL PASS: queued writes, streamed ~D bytes; ~A~%"
              (length bytes) "daemon survived connection close")
      (let ((notification (observe-window-rename client session window)))
        (assert (plusp (length notification)))
        (format t "CONTROL NOTIFICATION PASS: ~A~%"
                "explicit rename observed; captured name unchanged"))
      (multiple-value-bind (data provenance)
          (inspect-after-reconnect client session)
        (assert (= 1 (length data)))
        (assert (stringp (getf (aref data 0) :pane/id)))
        (format t "CONTROL RECONNECT PASS: generation ~D; ~A~%"
                (getf provenance :generation)
                "owned pane data remains after scope exit")))))
(assert (zerop (length (control:pending-cleanups))))
(assert (zerop (length (tm:pending-daemon-cleanups))))
