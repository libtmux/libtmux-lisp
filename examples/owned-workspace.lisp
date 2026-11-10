(require :asdf)
(asdf:load-asd (truename (merge-pathnames "../libtmux.asd" *load-truename*)))
(asdf:load-system "libtmux/workspace")

(defpackage #:libtmux.workspace.example
  (:use #:cl)
  (:local-nicknames (#:tm #:libtmux) (#:ws #:libtmux.workspace)))
(in-package #:libtmux.workspace.example)

;;; docs:owneddeclaration
(defun owned-description ()
  "Describe two windows and three panes without contacting tmux."
  (libtmux.workspace:make-workspace
   '(:schema "libtmux.lisp.workspace/2" :id "demo-workspace"
     :session
     (:id "main" :name "owned-demo"
      :environment #(("DEMO_LABEL" . "hello from Common Lisp"))
      :windows
      #((:id "code" :name "code" :index 2 :layout :tiled
         :panes #((:id "shell" :command #("/bin/cat"))
                  (:id "repl" :command #("/bin/cat"))))
        (:id "logs" :name "logs" :index 5
         :panes #((:id "tail" :command #("/bin/cat")))))))))
;;; docs:end

(defun observed-value (outcome)
  "Return a successful replacement observation or signal its retained failure."
  (when (tm:outcome-observation-error outcome) (error (tm:outcome-observation-error outcome)))
  (multiple-value-bind (value present-p) (tm:outcome-value outcome)
    (assert present-p)
    value))

(defun mapped-window (record id)
  "Return one logical window's mapping from an owned record; no I/O."
  (or (find id (getf record :windows) :key (lambda (item) (getf item :logical-id)) :test #'string=)
      (error "Missing logical window ~S" id)))

;;; docs:ownedapply
(defun apply-owned-description (client workspace)
  "Acquire, preview and apply explicitly; return the result and its owned record."
  (let* ((state (ws:fetch-workspace-state client workspace))
         (preview (ws:plan-workspace workspace state)))
    (assert (getf (ws:plan-data preview) :publish-p))
    (let ((result (ws:apply-workspace client workspace :total-timeout 30)))
      (assert (eq :succeeded (getf (ws:result-data result) :publication-status)))
      (values result (getf (ws:result-data result) :record)))))
;;; docs:end

;;; docs:ownedreconcile
(defun reconcile-owned-description (client workspace)
  "Preview permitted edits, then reacquire and apply them without replacing IDs."
  (let* ((state (ws:fetch-workspace-state client workspace))
         (preview (ws:plan-workspace workspace state :reconcile t)))
    (assert (getf (ws:plan-data preview) :publish-p))
    (ws:apply-workspace client workspace :reconcile t :total-timeout 30)))
;;; docs:end

;;; docs:ownedinspection
(defun inspect-stopped-workspace (client workspace)
  "Acquire incomplete ownership evidence; never retry the interrupted apply."
  (let* ((inspection (ws:inspect-workspace client workspace))
         (data (ws:inspection-data inspection)))
    (assert (getf data :complete-p))
    (assert (eq :busy (getf data :status)))
    data))
;;; docs:end

(defun exercise-owned-workspace (client program document)
  "Check native/file declarations, identity-preserving edits and stopped work."
  (let* ((base (owned-description))
         (loaded (ws:read-workspace document))
         (data (ws:workspace-data base))
         (session (getf data :session))
         (ready (symbol-name (gensym "owned-demo-ready-")))
         (unrelated (observed-value (tm:new-session client :name "outside" :command '("/bin/cat")))))
    (assert (equalp (ws:workspace-data base) (ws:workspace-data loaded)))
    (setf (getf session :environment)
          (concatenate 'vector (getf session :environment)
                       (vector (cons "DEMO_TMUX" program) (cons "DEMO_READY" ready))))
    (setf (aref (getf (aref (getf session :windows) 0) :panes) 0)
          (list :id "shell" :shell-command
                (concatenate 'string "printf '%s\\n' \"$DEMO_LABEL\"; "
                             "\"$DEMO_TMUX\" wait-for -S \"$DEMO_READY\"; exec /bin/cat")))
    (let ((workspace (ws:make-workspace data)))
      (multiple-value-bind (first before) (apply-owned-description client workspace)
        (assert (ws:result-created-p first))
        ;; The owned daemon scope also retires older tmux wait channels on failure.
        (assert (eq :succeeded
                    (tm:outcome-status
                     (tm:run-command client (list "-N" "wait-for" ready)
                                     :effect :read :timeout 1 :output-limit 4096))))
        (let* ((code (mapped-window before "code"))
               (shell-id (getf (aref (getf code :panes) 0) :physical-id))
               (shell (find shell-id (tm:panes (ws:result-snapshot first)) :key #'tm:id :test #'string=)))
          (multiple-value-bind (text outcome) (tm:capture-pane client shell)
            (assert (eq :succeeded (tm:outcome-status outcome)))
            (assert (search "hello from Common Lisp" text)))
          (let* ((next-data (ws:workspace-data workspace))
                 (next-session (getf next-data :session))
                 (window (aref (getf next-session :windows) 0)))
            (setf (getf next-session :name) "owned-renamed"
                  (getf window :name) "editors"
                  (getf window :layout) :even-vertical
                  (getf window :panes) (concatenate 'vector (getf window :panes)
                                                   #((:id "extra" :command #("/bin/cat")))))
            (let* ((desired (ws:make-workspace next-data))
                   (result (reconcile-owned-description client desired))
                   (after (getf (ws:result-data result) :record))
                   (after-code (mapped-window after "code")))
              (assert (string= (getf (getf before :session) :physical-id)
                               (getf (getf after :session) :physical-id)))
              (assert (string= (getf code :physical-id) (getf after-code :physical-id)))
              (assert (string= shell-id (getf (aref (getf after-code :panes) 0) :physical-id)))
              (assert (= 3 (length (getf after-code :panes))))
              (assert (string= "outside" (tm:name (tm:refresh client unrelated))))
              (assert (string= "owned-demo" (tm:name (find (getf (getf before :session) :physical-id)
                                                          (tm:sessions (ws:result-snapshot first))
                                                          :key #'tm:id :test #'string=))))
              (let* ((again (ws:apply-workspace client desired))
                     (again-data (ws:result-data again)))
                (assert (eq :unchanged (getf again-data :status)))
                (assert (null (getf again-data :publication-status))))
              (setf (getf window :layout) '(:custom "0000,80x24,0,0,0"))
              (let* ((invalid (ws:make-workspace next-data))
                     (failure (handler-case
                                  (progn (ws:apply-workspace client invalid :reconcile t)
                                         (error "Incorrect checksum was accepted"))
                                (ws:workspace-apply-failed (condition) condition))))
                (assert (eq :select-layout (ws:step-action (ws:failed-step failure))))
                (assert (plusp (length (ws:result-outcomes failure))))
                (assert (string= (getf after :revision)
                                 (getf (getf (ws:result-data failure) :record) :revision)))
                (inspect-stopped-workspace client invalid)))))))))

(let ((program (or (uiop:getenv "LIBTMUX_PROGRAM") "tmux"))
      (document (merge-pathnames "owned-workspace.json" *load-truename*)))
  (tm:with-daemon (daemon :program program)
    (tm:with-client (client :program (tm:daemon-program daemon) :socket-path (tm:daemon-socket-path daemon))
      (exercise-owned-workspace client (tm:daemon-program daemon) document)))
  (assert (zerop (length (tm:pending-daemon-cleanups))))
  (format t "OWNED WORKSPACE PASS: native/file declarations, printed-output notification, environment, stable IDs, reconcile, no-op, retained observations, unrelated session, stopped-work inspection~%"))
