(defpackage #:libtmux.examples
  (:use #:cl)
  (:local-nicknames (#:tm #:libtmux)
                    (#:q #:libtmux.query)
                    (#:j #:libtmux.json)
                    (#:ws #:libtmux.workspace))
  (:export #:inspect-workspace #:create-workspace #:observed-value
           #:apply-workspace-document #:terminate-owned-server #:configuration-report))

(in-package #:libtmux.examples)

;;; docs:configuration
(defun configuration-report (client session)
  "Read native configuration text; return an owned report and diagnostic outcomes."
  (let ((outcomes nil))
    (flet ((inspect-text (reader &rest options)
             (multiple-value-bind (text outcome) (apply reader client options)
               (push outcome outcomes)
               text)))
      (let ((report
              (list :options (inspect-text #'tm:show-options-text
                                           :scope :session :target session
                                           :name "status" :include-inherited t)
                    :hooks (inspect-text #'tm:show-hooks-text
                                         :scope :session :target session)
                    :environment (inspect-text #'tm:show-environment-text
                                               :scope :session :target session))))
        (values report (coerce (nreverse outcomes) 'simple-vector))))))
;;; docs:end

;;; docs:inventory
(defun inspect-workspace (socket-path &key (program "tmux"))
  "Acquire one graph from SOCKET-PATH; return owned session/window/pane data."
  (tm:with-client (client :program program :socket-path socket-path)
    (let ((snapshot (tm:fetch-snapshot client)))
      (loop for session across (tm:sessions snapshot)
            collect
            (list :session (tm:name session)
                  :windows
                  (loop for link across (tm:window-links session)
                        for window = (tm:window link)
                        collect (list :index (tm:index link)
                                      :name (tm:name window)
                                      :panes (map 'list #'tm:entity-data
                                                  (tm:panes window)))))))))
;;; docs:end

;;; docs:worker
(defun drive-worker (client session socket-path program worker-path receipt-path)
  "Launch a worker through argv, wait for readiness and verify input consumption.
WORKER-PATH names the shipped worker.sh; RECEIPT-PATH is in the owned demo directory.
Signals operational conditions without retrying a mutation. Calls block."
  (let* ((ready (symbol-name (gensym "example-ready-")))
         (consumed (symbol-name (gensym "example-consumed-")))
         (window (observed-value
                  (tm:new-window client session :name "worker"
                                 :command (list "/bin/sh" worker-path program
                                                socket-path ready consumed receipt-path))))
         (pane (aref (tm:panes window) 0))
         (message "release #{literal}; λ"))
    (tm:run-command client (list "-N" "wait-for" ready)
                    :effect :read :timeout 1 :output-limit 4096)
    (tm:send-text client pane message :enter t)
    (tm:run-command client (list "-N" "wait-for" consumed)
                    :effect :read :timeout 1 :output-limit 4096)
    (let ((receipt (uiop:read-file-string receipt-path :external-format :utf-8)))
      (assert (string= message receipt))
      (list :consumed receipt :pane (tm:id pane)))))
;;; docs:end

;;; docs:condition
(defun cancelled-read (client)
  "Demonstrate typed failure evidence using a read cancelled before acquisition."
  (let ((token (tm:make-cancellation-token)))
    (tm:cancel token)
    (handler-case
        (progn (tm:fetch-snapshot client :cancel-token token)
               (error "A cancelled read unexpectedly completed"))
      (tm:command-cancelled (condition)
        (let ((outcome (tm:error-outcome condition)))
          (list :condition (type-of condition)
                :status (and outcome (tm:outcome-status outcome))
                :phase (and outcome (tm:outcome-phase outcome))))))))
;;; docs:end

;;; docs:outcome
(defun observed-value (outcome)
  "Return an operation's observed value, or signal its observation failure."
  (when (tm:outcome-observation-error outcome)
    (error (tm:outcome-observation-error outcome)))
  (multiple-value-bind (value present-p) (tm:outcome-value outcome)
    (unless present-p
      (error "This operation did not return an observation"))
    value))
;;; docs:end

;;; docs:workspace
(defun create-workspace (client)
  "Extend the demo's WORK session; return a fresh captured graph.
Creates a logs window, a second editor pane, a review session and a shared link.
The caller owns the isolated daemon; repeating this recipe there is an error."
  (let* ((before (tm:fetch-snapshot client))
         (work (find "work" (tm:sessions before) :key #'tm:name :test #'string=)))
    (unless work (error "Start the demo's WORK session first"))
    (let* ((editor-link (aref (tm:window-links work) 0))
           (editor (tm:window editor-link))
           (pane (aref (tm:panes editor) 0))
           (logs (observed-value
                  (tm:new-window client work :name "logs" :command '("/bin/cat"))))
           (review (observed-value
                    (tm:new-session client :name "review" :window-name "notes"
                                          :command '("/bin/cat")))))
      (tm:split-pane client pane :direction :horizontal :command '("/bin/cat"))
      (tm:link-window client editor-link review 7)
      (tm:rename-window client logs "logs #{literal}")
      (tm:fetch-snapshot client))))
;;; docs:end

;;; docs:selection
(defun wide-active-panes (snapshot)
  "Select captured active panes at least 40 cells wide; no tmux commands."
  (loop for pane across (tm:panes snapshot)
        when (and (tm:active-p pane) (>= (tm:width pane) 40))
          collect (tm:entity-data pane)))
;;; docs:end

;;; docs:query
(defparameter *wide-active-filter*
  (q:compile-filter
   :pane
   '(:and (:= :pane/active t)
          (:>= :pane/width 40))))

(defun wide-active-pane-data (snapshot)
  "Return owned data for captured active panes at least 40 cells wide; no I/O."
  (map 'vector #'tm:entity-data
       (q:matching *wide-active-filter* (tm:panes snapshot))))
;;; docs:end

;;; docs:relation
(defparameter *active-session-filter*
  (q:compile-filter
   :session
   '(:any :session/window-links
     (:is :link/window
      (:any :window/panes
       (:= :pane/active t))))))

(defun active-session-data (snapshot)
  "Return owned data for sessions with an active pane; no I/O."
  (map 'vector #'tm:entity-data
       (q:items
        (q:where (q:from (tm:sessions snapshot) :model :session)
                 *active-session-filter*))))
;;; docs:end

;;; docs:regex
(defparameter *cat-command-filter*
  (q:compile-filter
   :pane
   '(:regex-full-match :pane/current-command
     (:cl-ppcre "CAT" :case-insensitive-mode t))))

(defun cat-pane-data (snapshot)
  "Return owned data for captured panes whose command is exactly cat; no I/O."
  (map 'vector #'tm:entity-data
       (q:matching *cat-command-filter* (tm:panes snapshot))))
;;; docs:end

;;; docs:filterdocument
(defun round-trip-filter-document (snapshot)
  "Round-trip the checked regex filter and apply it to one retained snapshot."
  (let* ((document (j:write-filter *cat-command-filter*))
         (restored (j:read-filter document :allow-regex t)))
    (values document
            (map 'vector #'tm:entity-data
                 (q:matching restored (tm:panes snapshot))))))
;;; docs:end

;;; docs:workspaceconfig
(defun apply-workspace-document (client pathname)
  "Plan and apply one bounded workspace document through explicit CLIENT.
Return the local plan steps and retained application result as two values."
  (let* ((workspace (ws:read-workspace pathname))
         (snapshot (tm:fetch-snapshot client))
         (plan (ws:plan-workspace workspace snapshot)))
    (values (ws:plan-steps plan)
            (ws:apply-workspace client workspace))))
;;; docs:end

;;; docs:buffers
(defun round-trip-bytes (client)
  "Store and retrieve a named binary buffer, including NUL and invalid UTF-8."
  (let ((bytes (make-array 5 :element-type '(unsigned-byte 8)
                           :initial-contents '(0 10 92 195 255))))
    (tm:set-buffer client bytes :name "example bytes")
    (multiple-value-bind (actual outcome)
        (tm:show-buffer client :name "example bytes")
      (assert (eq :succeeded (tm:outcome-status outcome)))
      (assert (equalp bytes actual))
      actual)))
;;; docs:end

;;; docs:termination
(defun terminate-owned-server (socket-path &key (program "tmux"))
  "Terminate the explicitly selected owned server and return its proven outcome."
  (tm:with-client (client :program program :socket-path socket-path)
    (let ((outcome (tm:kill-server client)))
      (assert (eq :succeeded (tm:outcome-status outcome)))
      (assert (eq :server-terminated (tm:outcome-phase outcome)))
      outcome)))
;;; docs:end
