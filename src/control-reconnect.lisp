(in-package #:libtmux.internal)

(define-condition control-origin-stale (libtmux:stale-target) ())

(defun stale-control-origin (peer client)
  (error 'control-origin-stale :client client :target peer
         :message "Control origin changed; acquire fresh observations and open a new connection"))

(defun require-control-origin (peer client)
  "Refuse stale local authority before I/O and again after initial capture."
  (unless (and (eq client (control-peer-origin-client peer))
               (eq (slot-value client 'libtmux::context) (control-peer-origin-context peer))
               (eql (slot-value client 'libtmux::generation) (control-peer-origin-generation peer)))
    (stale-control-origin peer client)))

(defun control-reconnect-session (peer client capture)
  "Resolve the original exact session only under the retained daemon witness."
  (unless (equal (control-peer-origin-witness peer)
                 (witness-values (slot-value client 'libtmux::witness)))
    (stale-control-origin peer client))
  (or (find (control-peer-origin-session peer) (libtmux:sessions capture)
            :key #'libtmux:id :test #'string=)
      (stale-control-origin peer client)))

(defun reconnect-control-peer (peer &key (timeout 30) close-function
                                       (request-limit (control-peer-request-limit peer))
                                       (event-limit (control-peer-event-limit peer))
                                       (event-byte-limit (control-peer-event-byte-limit peer))
                                       (reply-byte-limit (control-peer-reply-byte-limit peer)))
  "Retire PEER, renew its borrowed client's generation, recapture and attach.
Return the new peer and pre-attachment snapshot. Never replay requests or
roll back generation renewal after a failed cutover."
  (check-type peer control-peer)
  (check-control-limits timeout request-limit event-limit event-byte-limit reply-byte-limit)
  (let ((client (control-peer-origin-client peer)))
    (unless (typep client 'libtmux:client) (stale-control-origin peer client))
    (call-with-operation
     client nil
     (lambda (token)
       (require-control-origin peer client)
       (let* ((start (monotonic-seconds))
              (budget (make-capture-budget :start start :deadline (+ start timeout)
                                           :remaining (slot-value client 'libtmux::output-limit)
                                           :row-limit 100000 :field-limit 1048576))
              (before (capture-with-retries client token budget 100000)))
         (require-control-origin peer client)
         (control-reconnect-session peer client before)
         (check-command-capability client :control "3.8")
         (check-capture-budget budget token)
         (let ((*operation-client* nil))
           (if close-function (funcall close-function) (close-control-peer peer)))
         (unless (control-peer-finished peer)
           (retain-control-peer peer)
           (error 'libtmux:cleanup-failed :resource peer
                  :message "Old control close returned before retiring its worker"))
         ;; Retirement commits the cutover even if its budget expired during close.
         (invalidate-client-generation client)
         (check-capture-budget budget token)
         (let* ((capture (capture-with-retries client token budget 100000))
                (current (control-reconnect-session peer client capture))
                (replacement (attach-control-peer client current token budget (slot-value client 'libtmux::witness)
                               :request-limit request-limit :event-limit event-limit
                               :event-byte-limit event-byte-limit :reply-byte-limit reply-byte-limit)))
           (values replacement capture)))))))
