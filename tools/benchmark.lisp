;;; Native workloads for the optional transport comparison. The Python driver
;;; owns evidence/provenance; every timed operation here uses the Lisp library.
(require :asdf)
(setf *compile-verbose* nil *load-verbose* nil)
(declaim (sb-ext:muffle-conditions sb-ext:compiler-note))
(asdf:load-asd (truename (merge-pathnames "../libtmux.asd" *load-truename*)))
(asdf:load-system "libtmux/control")

(defpackage #:libtmux.benchmark
  (:use #:cl)
  (:local-nicknames (#:tm #:libtmux) (#:control #:libtmux.control)))
(in-package #:libtmux.benchmark)

(defun row (stream &rest fields)
  "Write a tab-separated evidence row; fields contain no tabs or newlines."
  (loop for field in fields for separator = "" then #\Tab
        do (write-string (string separator) stream)
           (cond ((null field) (write-char #\- stream))
                 ((floatp field) (format stream "~,9F" field))
                 (t (princ field stream))))
  (terpri stream)
  (finish-output stream))

(defun ticks ()
  "Return monotonic nanosecond units from the qualified SBCL/Linux clock."
  (multiple-value-bind (seconds nanoseconds) (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ (* seconds 1000000000) nanoseconds)))

(defun seconds-since (start)
  (/ (- (ticks) start) 1d9))

(defun measured (stream kind phase iteration counter function)
  "Measure a completed phase; return its value and write checked counters.
SBCL's allocation counter is process-wide, including worker allocation and
counter overhead. RESULT-BYTES counts application output, not wire framing."
  (let* ((launches (funcall counter)) (allocated (sb-ext:get-bytes-consed))
         (start (ticks))
         (bytes (funcall function))
         (seconds (seconds-since start))
         (allocation (- (sb-ext:get-bytes-consed) allocated)))
    (assert (and (>= seconds 0) (>= allocation 0)))
    (row stream kind phase iteration seconds allocation (- (funcall counter) launches) bytes)
    bytes))

(defun checked-reply (request expected)
  (multiple-value-bind (result delivery) (control:await-request request :timeout 2)
    (assert (eq :ready delivery))
    (assert (eq :completed (getf result :status)))
    (assert (equalp expected (getf result :output)))
    (length (getf result :output))))

(defun read-batch (client connection lane count argv expected)
  "Run identical literal reads through one selected public API lane."
  (ecase lane
    (:subprocess
     (loop repeat count for outcome = (tm:run-command client argv :effect :read :timeout 2)
           for bytes = (tm:outcome-stdout outcome)
           do (assert (eq :succeeded (tm:outcome-status outcome)))
              (assert (equalp expected bytes))
           sum (length bytes)))
    (:control-serial
     (loop repeat count sum (checked-reply
                             (control:submit-command connection argv :effect :read :timeout 2) expected)))
    (:control-queued
     (let ((requests (loop repeat count collect
                           (control:submit-command connection argv :effect :read :timeout 2))))
       (loop for request in requests sum (checked-reply request expected))))))

(defun cells (stream client connection samples commands panes counter)
  (let* ((payload (make-string 256 :initial-element #\x))
         (argv (list "display-message" "-p" payload))
         (expected (map '(vector (unsigned-byte 8)) #'char-code (format nil "~A~%" payload)))
         (lanes (append '(:subprocess) (when connection '(:control-serial :control-queued)) '(:snapshot))))
    (labels ((work (lane)
               (if (eq lane :snapshot)
                   (progn
                     (assert (= panes (length (tm:panes (tm:fetch-snapshot client)))))
                     nil)
                   (read-batch client connection lane commands argv expected))))
      (loop repeat 3 do (dolist (lane lanes) (work lane)))
      (loop for iteration below samples
            for offset = (mod iteration (length lanes))
            for order = (append (nthcdr offset lanes) (subseq lanes 0 offset))
            do (dolist (lane order)
                 (measured stream "sample" (string-downcase lane) iteration counter
                           (lambda () (work lane))))))))

(defun run (stream program samples commands panes)
  "Measure one stable owned fixture, with setup and cleanup outside samples."
  (row stream "meta" "sbcl" (lisp-implementation-version))
  (row stream "meta" "asdf" (asdf:asdf-version))
  (row stream "meta" "clock" "SB-UNIX:CLOCK-GETTIME/CLOCK-MONOTONIC")
  (row stream "meta" "clock-units-per-second" 1000000000)
  (let ((owner nil) (socket nil) (launches 0))
    (tm:with-daemon (daemon :program program)
      (setf owner daemon socket (tm:daemon-socket-path daemon))
      (tm:with-client (client :program (tm:daemon-program daemon) :socket-path socket)
        (row stream "meta" "tmux" (tm:tmux-version client))
        (let ((libtmux.internal::*process-launched-hook* (lambda (job) (declare (ignore job)) (incf launches)))
              (counter (lambda () launches)))
          (measured stream "setup" "fixture" 0 counter
                    (lambda ()
                      (let ((outcome (tm:new-session client :name "benchmark" :width 160 :height 64
                                                            :command '("/bin/cat"))))
                        (assert (eq :succeeded (tm:outcome-status outcome)))
                        (when (tm:outcome-observation-error outcome) (error (tm:outcome-observation-error outcome))))
                      (loop repeat (1- panes)
                            do (tm:run-command client '("split-window" "-d" "-t" "=benchmark:0" "--" "/bin/cat"
                                                        ";" "select-layout" "-t" "=benchmark:0" "tiled")
                                               :effect :mutation :timeout 2))
                      nil))
          (let* ((snapshot (tm:fetch-snapshot client))
                 (session (aref (tm:sessions snapshot) 0)))
            (assert (= panes (length (tm:panes snapshot))))
            (if (libtmux.internal::version-at-least-p (tm:tmux-version client) "3.7")
                (let ((start (ticks)) (allocated (sb-ext:get-bytes-consed))
                      (started launches) (close-start nil) (close-allocated nil) (close-launches nil))
                  (row stream "meta" "control" "available")
                  (control:with-connection (connection client session :request-limit commands)
                    (row stream "setup" "control-open" 0 (seconds-since start)
                         (- (sb-ext:get-bytes-consed) allocated) (- launches started) nil)
                    (cells stream client connection samples commands panes counter)
                    (setf close-start (ticks) close-allocated (sb-ext:get-bytes-consed)
                          close-launches launches))
                  (row stream "cleanup" "control-close" 0 (seconds-since close-start)
                       (- (sb-ext:get-bytes-consed) close-allocated) (- launches close-launches) nil))
                (progn
                  (row stream "meta" "control" "unsupported-before-3.7")
                  (cells stream client nil samples commands panes counter)))))))
    (assert (eq :closed (tm:daemon-state owner)))
    (assert (not (probe-file socket)))
    (assert (zerop (length (tm:pending-daemon-cleanups))))
    (assert (zerop (length (control:pending-cleanups))))
    (row stream "cleanup" "fixture" "PASS")))

(let* ((arguments (uiop:command-line-arguments))
       (program (first arguments)) (samples (parse-integer (second arguments)))
       (commands (parse-integer (third arguments))) (panes (parse-integer (fourth arguments)))
       (records (fifth arguments)))
  (assert (= 5 (length arguments)))
  (assert (<= 6 samples 200))
  (assert (<= 1 commands 32))
  (assert (<= 1 panes 16))
  (let ((stream (open records :direction :output :if-exists :error)))
    (unwind-protect (run stream program samples commands panes)
      (close stream :abort nil))))
