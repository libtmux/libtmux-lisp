(in-package #:libtmux.tests)

(in-suite workspace)

(defun planner-state (&key drift grouped unsafe extra-pane unmanaged-pane shared)
  (let* ((snapshot (owned-state-graph :extra-pane (or extra-pane unmanaged-pane) :shared shared))
         (record (owned-committed-data))
         (declaration (getf record :declaration))
         (session (getf declaration :session))
         (windows (getf session :windows))
         (mapping (getf record :windows)))
    (unless drift
      (setf (getf session :name) "renamed"
            (getf (getf record :session) :name) "renamed"
            (getf (aref windows 0) :name) "drifted"
            (getf (aref mapping 0) :name) "drifted"
            (getf (aref mapping 0) :layout) "changed"
            (getf (aref mapping 1) :layout) "changed"))
    (when extra-pane
      (setf (getf (aref windows 0) :panes)
            (concatenate 'vector (getf (aref windows 0) :panes) #((:id "last")))
            (getf (aref mapping 0) :panes)
            (concatenate 'vector (getf (aref mapping 0) :panes) #((:logical-id "last" :physical-id "%23")))))
    (setf record (workspace-call :owned-record-data (workspace-call :make-owned-record :committed record))
          declaration (getf record :declaration))
    (make-instance 'libtmux.workspace::owned-state :snapshot snapshot :outcomes #()
                   :data (list :status :owned :declaration declaration :committed record
                               :groups (vector (cons "$8" grouped))
                               :geometry
                               (workspace-call :parse-owned-geometry
                                               (format nil "~{~A~}"
                                                       (loop for window across (libtmux:windows snapshot)
                                                             append (loop for pane across (libtmux:panes window)
                                                                          collect (geometry-row (libtmux:id window) (libtmux:id pane)
                                                                                                (if unsafe "1" "0") "0" "0"))))
                                               snapshot "3.8")))))

(defun planner-description (state)
  (getf (workspace-call :owned-state-data state) :declaration))

(defun owned-plan (data state &rest options)
  (apply #'workspace-call :plan-owned-workspace
         (workspace-call :make-owned-declaration data) state options))

(defun owned-plan-actions (plan)
  (map 'list #'libtmux.workspace:step-action (workspace-call :owned-plan-steps plan)))

(test owned-planner-noop-is-local-and-ignores-unrelated-window
  (let* ((state (planner-state)) (data (planner-description state))
         (libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (error "Local planning launched I/O")))
         (plan (owned-plan data state))
         (projection (workspace-call :owned-plan-data plan)))
    (is (null (owned-plan-actions plan)))
    (is (zerop (length (getf projection :changes))))
    (is (zerop (length (getf projection :drift))))
    (is (plusp (length (getf projection :context))))
    (is (null (getf projection :publish-p)))
    (setf (getf projection :publish-p) t)
    (is (null (getf (workspace-call :owned-plan-data plan) :publish-p)))))

(test owned-planner-keeps-declaration-edits-separate-from-observed-drift
  (let* ((state (planner-state)) (data (planner-description state)))
    (setf (getf (getf data :session) :name) "renamed-again"
          (getf (aref (getf (getf data :session) :windows) 0) :name) "new-name")
    (signals libtmux.workspace:workspace-conflict (owned-plan data state))
    (let* ((plan (owned-plan data state :reconcile t))
           (projection (workspace-call :owned-plan-data plan)))
      (is (equal '(:rename-session :rename-window) (owned-plan-actions plan)))
      (is (= 2 (length (getf projection :changes))))
      (is (zerop (length (getf projection :drift))))
      (is-true (getf projection :publish-p))))
  (let* ((state (planner-state :drift t))
         (plan (owned-plan (planner-description state) state :reconcile t))
         (projection (workspace-call :owned-plan-data plan)))
    (is (zerop (length (getf projection :changes))))
    (is (plusp (length (getf projection :drift))))
    (is-true (getf projection :publish-p))
    (is (equal '(:rename-session :rename-window :select-layout :select-layout)
               (owned-plan-actions plan)))
    (signals libtmux.workspace:workspace-conflict (owned-plan (planner-description state) state))))

(test owned-planner-refuses-unsupported-edits-before-producing-a-plan
  (let ((state (planner-state)))
    (dolist (edit (list (lambda (data) (setf (getf data :id) "foreign"))
                       (lambda (data) (setf (getf (getf data :session) :id) "foreign"))
                       (lambda (data) (setf (getf (getf data :session) :cwd) "/changed"))
                       (lambda (data) (setf (getf (getf data :session) :environment) #()))
                       (lambda (data)
                         (setf (getf (getf data :session) :windows)
                               (subseq (getf (getf data :session) :windows) 0 1)))
                       (lambda (data)
                         (setf (getf (aref (getf (getf data :session) :windows) 0) :index) 5))
                       (lambda (data)
                         (setf (getf (aref (getf (aref (getf (getf data :session) :windows) 0) :panes) 0)
                                     :command) #("/bin/CAT")))))
      (let ((data (planner-description state)))
        (funcall edit data)
        (signals libtmux.workspace:workspace-conflict (owned-plan data state :reconcile t))))))

(test owned-planner-metadata-only-edits-require-publication
  (let* ((state (planner-state)) (data (planner-description state))
         (session (getf data :session)) (windows (getf session :windows)))
    (remf (aref windows 0) :index)
    (setf (getf session :windows) (reverse windows))
    (let* ((plan (owned-plan data state :reconcile t))
           (projection (workspace-call :owned-plan-data plan)))
      (is (null (owned-plan-actions plan)))
      (is (plusp (length (getf projection :changes))))
      (is-true (getf projection :publish-p)))))

(test owned-planner-scopes-geometry-and-group-admission-to-effects
  (dolist (state (list (planner-state :grouped t) (planner-state :unsafe t)))
    (is (null (owned-plan-actions (owned-plan (planner-description state) state)))))
  (let* ((state (planner-state :grouped t)) (data (planner-description state)))
    (setf (getf (getf data :session) :name) "group-rename")
    (signals libtmux.workspace:workspace-conflict (owned-plan data state :reconcile t)))
  (let* ((state (planner-state :unsafe t)) (data (planner-description state))
         (window (aref (getf (getf data :session) :windows) 0)))
    (setf (getf window :name) "safe-rename")
    (is (equal '(:rename-window) (owned-plan-actions (owned-plan data state :reconcile t)))))
  (let* ((state (planner-state :unsafe t)) (data (planner-description state)))
    (setf (getf (aref (getf (getf data :session) :windows) 0) :layout) :tiled)
    (signals libtmux.workspace:workspace-conflict (owned-plan data state :reconcile t))))

(test owned-planner-inserts-before-between-and-after-logical-anchors
  (let* ((state (planner-state :extra-pane t)) (data (planner-description state))
         (window (aref (getf (getf data :session) :windows) 0))
         (old-panes (getf window :panes)))
    (remf window :layout)
    (setf (getf window :panes)
          (vector (list :id "leading") (aref old-panes 0) (list :id "middle")
                  (aref old-panes 1) (list :id "trailing")))
    (let* ((plan (owned-plan data state :reconcile t))
           (steps (workspace-call :owned-plan-steps plan))
           (splits (remove-if (lambda (step) (not (eq :split-pane (libtmux.workspace:step-action step)))) steps)))
      (is (equal '(:split-pane :select-layout :split-pane :select-layout :split-pane) (owned-plan-actions plan)))
      (is (equal '("first" "first" "last")
                 (map 'list (lambda (step) (getf (libtmux.workspace:step-data step) :anchor-id)) splits)))
      (is (equal '(t nil nil)
                 (map 'list (lambda (step) (getf (libtmux.workspace:step-data step) :before)) splits))))))

(test owned-planner-refuses-reorder-sharing-and-unmanaged-geometry-effects
  (let* ((state (planner-state :extra-pane t)) (data (planner-description state))
         (window (aref (getf (getf data :session) :windows) 0)))
    (setf (getf window :panes) (reverse (getf window :panes)))
    (signals libtmux.workspace:workspace-conflict (owned-plan data state :reconcile t)))
  (dolist (state (list (planner-state :shared t) (planner-state :unmanaged-pane t)))
    (is (null (owned-plan-actions (owned-plan (planner-description state) state))))
    (let ((data (planner-description state)))
      (setf (getf (aref (getf (getf data :session) :windows) 0) :layout) :tiled)
      (signals libtmux.workspace:workspace-conflict (owned-plan data state :reconcile t))))
  (let* ((state (planner-state :shared t)) (data (planner-description state)))
    (setf (getf (aref (getf (getf data :session) :windows) 1) :name) "unshared-change")
    (is (equal '(:rename-window) (owned-plan-actions (owned-plan data state :reconcile t))))))

(test owned-planner-reserves-explicit-new-windows-before-automatic-windows
  (let* ((state (planner-state)) (data (planner-description state)) (session (getf data :session)))
    (setf (getf session :windows)
          (concatenate 'vector (getf session :windows)
                       #((:id "auto" :name "same" :panes #((:id "auto-pane")))
                         (:id "reserved" :name "same" :index 0 :panes #((:id "reserved-pane"))))))
    (let* ((plan (owned-plan data state :reconcile t))
           (steps (workspace-call :owned-plan-steps plan)))
      (is (equal '(:create-window :create-window) (owned-plan-actions plan)))
      (is (equal '("reserved" "auto")
                 (map 'list (lambda (step) (getf (libtmux.workspace:step-data step) :window-id)) steps)))
      (is (= 0 (getf (libtmux.workspace:step-data (aref steps 0)) :index)))
      (is (not (nth-value 1 (workspace-call :plist-value
                                          (libtmux.workspace:step-data (aref steps 1)) :index)))))
    (setf (getf (aref (getf session :windows) 3) :index) 7)
    (signals libtmux.workspace:workspace-conflict (owned-plan data state :reconcile t))))

(test owned-planner-vacancy-uses-owned-inputs-and-rechecks-name-freedom
  (let* ((snapshot (owned-state-graph))
         (data (planner-description (planner-state)))
         (session (getf data :session)))
    (setf (getf session :name) "vacant")
    (let* ((state (make-instance 'libtmux.workspace::owned-state :snapshot snapshot :outcomes #()
                                :data (list :status :vacant :declaration (workspace-call :deep-copy data))))
           (plan (owned-plan data state))
           (steps (workspace-call :owned-plan-steps plan))
           (first (libtmux.workspace:step-data (aref steps 0))))
      (is (equal '(:create-session :move-window :select-layout :create-window) (owned-plan-actions plan)))
      (is (string= "main" (getf first :session-id)))
      (is (string= "editor" (getf first :window-id)))
      (is (string= "first" (getf first :pane-id)))
      (is (equalp #("/bin/cat") (getf first :command)))
      (is (equalp #(("A" . "") ("Z" . "last")) (getf first :environment)))
      (is-true (getf (workspace-call :owned-plan-data plan) :publish-p))
      (setf (getf session :name) "renamed")
      (signals libtmux.workspace:workspace-conflict (owned-plan data state)))))

(test owned-planner-refuses-observed-owned-pane-reordering
  (let* ((base (planner-state :extra-pane t)) (data (workspace-call :owned-state-data base))
         (record (getf data :committed))
         (window (aref (getf (getf (getf record :declaration) :session) :windows) 0))
         (mapped (aref (getf record :windows) 0)))
    (setf (getf window :panes) (reverse (getf window :panes))
          (getf mapped :panes) (reverse (getf mapped :panes))
          (getf data :declaration) (getf record :declaration))
    (let ((state (make-instance 'libtmux.workspace::owned-state :snapshot (workspace-call :owned-state-snapshot base)
                                :data data :outcomes #())))
      (signals libtmux.workspace:workspace-conflict
        (owned-plan (planner-description state) state :reconcile t)))))

(test owned-planner-repairs-realized-layout-without-inventing-a-source
  (let* ((state (planner-state :drift t)) (data (workspace-call :owned-state-data state))
         (record (getf data :committed)))
    (remf (aref (getf (getf (getf record :declaration) :session) :windows) 0) :layout)
    (setf (getf data :declaration) (getf record :declaration))
    (let* ((state (make-instance 'libtmux.workspace::owned-state :snapshot (workspace-call :owned-state-snapshot state)
                                 :data data :outcomes #()))
           (plan (owned-plan (planner-description state) state :reconcile t))
           (layouts (remove-if (lambda (step) (not (eq :select-layout (libtmux.workspace:step-action step))))
                               (workspace-call :owned-plan-steps plan))))
      (is (equal '(:custom "realized-1") (getf (libtmux.workspace:step-data (aref layouts 0)) :layout))))))

(test owned-planner-inspection-and-steps-own-their-data
  (let* ((state (planner-state)) (data (planner-description state))
         (session (getf data :session)))
    (setf (getf session :name) (copy-seq "new-name"))
    (let* ((plan (owned-plan data state :reconcile t))
           (steps (workspace-call :owned-plan-steps plan))
           (step (aref steps 0)) (copy (libtmux.workspace:step-data step)))
      (setf (char (getf session :name) 0) #\X
            (char (getf copy :name) 0) #\X
            (aref steps 0) nil)
      (is (string= "new-name" (getf (libtmux.workspace:step-data step) :name)))
      (is (equal '(:rename-session) (owned-plan-actions plan))))))

(test owned-planner-refuses-a-captured-session-name-collision
  (let* ((base (planner-state))
         (snapshot
           (libtmux.internal::build-snapshot
            (gensym "PLANNER-NAMES-") 1
            '(:server/pid 7 :server/start-time 10 :server/process-start 20
              :server/socket-device 1 :server/socket-inode 2 :server/version "3.8")
            (synthetic-rows :session '(("session/1" "$8" "renamed" "1" "0" "3")
                                      ("session/1" "$9" "occupied" "1" "0" "1")))
            (synthetic-rows :window-link
              '(("window-link/1" "$8" "1" "@10" "drifted" "120" "30" "1" "1" "changed")
                ("window-link/1" "$8" "4" "@11" "same" "120" "30" "1" "0" "changed")
                ("window-link/1" "$8" "7" "@12" "unmanaged" "120" "30" "1" "0" "other")
                ("window-link/1" "$9" "0" "@12" "unmanaged" "120" "30" "1" "1" "other")))
            (synthetic-rows :pane
              '(("pane/1" "$8" "1" "@10" "%2520" "0" "1" "120" "30" "cat" "/" "" "100" "0" "cat")
                ("pane/1" "$8" "4" "@11" "%2521" "0" "1" "120" "30" "cat" "/" "" "100" "0" "cat")
                ("pane/1" "$8" "7" "@12" "%2522" "0" "1" "120" "30" "cat" "/" "" "100" "0" "cat")
                ("pane/1" "$9" "0" "@12" "%2522" "0" "1" "120" "30" "cat" "/" "" "100" "0" "cat"))) #()))
         (data (workspace-call :owned-state-data base)))
    (setf (getf data :groups) #(("$8") ("$9")))
    (let* ((state (make-instance 'libtmux.workspace::owned-state :snapshot snapshot :data data :outcomes #()))
           (wanted (planner-description state)))
      (setf (getf (getf wanted :session) :name) "occupied")
      (signals libtmux.workspace:workspace-conflict (owned-plan wanted state :reconcile t)))))
