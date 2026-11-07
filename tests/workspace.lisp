(in-package #:libtmux.tests)

(in-suite workspace)

(defun example-workspace-data ()
  (list :schema (copy-seq "libtmux.lisp.workspace/1")
        :session
        (list :name (copy-seq "workspace")
              :cwd (copy-seq "/srv/app")
              :windows
              (vector
               (list :name (copy-seq "editor")
                     :index 1
                     :layout :tiled
                     :panes
                     (vector (list :command (vector (copy-seq "/bin/cat")))
                             (list :cwd (copy-seq "/srv/app/sub")
                                   :command (vector (copy-seq "/bin/cat")))))
               (list :name (copy-seq "shell")
                     :index 4
                     :panes (vector (list :command (vector (copy-seq "/bin/cat")))))))))

(defun workspace-call (name &rest arguments)
  (apply #'uiop:symbol-call :libtmux.workspace name arguments))

(defun workspace-condition-p (condition name)
  (let ((symbol (find-symbol (string name) :libtmux.workspace)))
    (and symbol (typep condition symbol))))

(defmacro signals-workspace (name &body body)
  `(handler-case
       (progn ,@body (fail "Expected ~A" ,name))
     (condition (condition)
       (if (workspace-condition-p condition ,name)
           (is-true t)
           (error condition)))))

(test workspace-native-data-is-owned-and-plans-deterministically
  (let* ((source (example-workspace-data))
         (workspace (workspace-call :make-workspace source))
         (data (workspace-call :workspace-data workspace))
         (plan (workspace-call :plan-workspace workspace))
         (steps (workspace-call :plan-steps plan)))
    (setf (char (getf (getf source :session) :name) 0) #\X
          (char (getf (getf data :session) :name) 0) #\Y
          (aref steps 0) nil)
    (is (string= "workspace"
                 (getf (getf (workspace-call :workspace-data workspace) :session)
                       :name)))
    (let ((actions
            (map 'list
                 (lambda (step) (workspace-call :step-action step))
                 (workspace-call :plan-steps plan))))
      (is (equal '(:create-session :move-window :split-pane :select-layout
                   :create-window)
                 actions)))
    (let* ((first (aref (workspace-call :plan-steps plan) 0))
           (step-data (workspace-call :step-data first)))
      (setf (char (getf step-data :session-name) 0) #\Z)
      (is (string= "workspace"
                   (getf (workspace-call :step-data first) :session-name))))))

(test workspace-native-data-rejects-open-or-unsafe-shapes
  (dolist
      (data
       (list
        nil
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #()) :extra t)
        '(:schema "libtmux.lisp.workspace/1"
          :schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #()))
        '(:schema "foreign" :session (:name "x" :windows #()))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "" :windows #()))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "same" :panes #())
                                            (:name "same" :panes #()))))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "w" :index -1
                                           :panes #(())))))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "w" :layout :unknown
                                           :panes #(())))))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "w"
                                           :panes #((:command #()))))))
        '(:schema "libtmux.lisp.workspace/1"
          :session (:name "x" :windows #((:name "w"
                                           :panes #((:command #("-bad")))))))))
    (signals-workspace :invalid-workspace
      (workspace-call :make-workspace data))))

(test workspace-native-data-rejects-cycles-and-limit-exhaustion
  (let ((cycle (list :schema "libtmux.lisp.workspace/1")))
    (setf (cddr cycle) cycle)
    (signals-workspace :invalid-workspace
      (workspace-call :make-workspace cycle)))
  (signals-workspace :invalid-workspace
    (workspace-call :make-workspace (example-workspace-data) :max-windows 1))
  (signals-workspace :invalid-workspace
    (workspace-call :make-workspace (example-workspace-data) :max-panes 1))
  (signals-workspace :invalid-workspace
    (workspace-call :make-workspace (example-workspace-data) :max-argv 0)))

(defun workspace-snapshot (&key (name "workspace")
                                (windows '(("editor" 1 2) ("shell" 4 1))))
  (let ((session-id "$21")
        (link-rows nil)
        (pane-rows nil))
    (loop for (window-name index pane-count) in windows
          for window-number from 31
          for window-id = (format nil "@~D" window-number)
          do (push (list "window-link/1" session-id (write-to-string index)
                         window-id window-name "120" "30"
                         (write-to-string pane-count)
                         (if (= index (second (first windows))) "1" "0") "")
                   link-rows)
             (dotimes (pane-index pane-count)
               (push (list "pane/1" session-id (write-to-string index) window-id
                           (format nil "%25~D" (+ (* window-number 10) pane-index))
                           (write-to-string pane-index)
                           (if (zerop pane-index) "1" "0") "120" "30" "cat"
                           "/srv/app" "" "100" "0" "cat")
                     pane-rows)))
    (libtmux.internal::build-snapshot
     (gensym "WORKSPACE-SERVER-") 1
     '(:server/socket-path "workspace.sock" :server/version "3.8")
     (synthetic-rows
      :session
      (list (list "session/1" session-id name "1" "0"
                  (write-to-string (length windows)))))
     (synthetic-rows :window-link (nreverse link-rows))
     (synthetic-rows :pane (nreverse pane-rows))
     #())))

(test workspace-planning-reuses-only-an-exact-captured-topology
  (let* ((workspace (workspace-call :make-workspace (example-workspace-data)))
         (snapshot (workspace-snapshot))
         (calls 0)
         (libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (incf calls))))
    (is (zerop (length (workspace-call :plan-steps
                                       (workspace-call :plan-workspace workspace snapshot)))))
    (is (zerop calls))
    (dolist (conflict
             (list (workspace-snapshot :name "other")
                   (workspace-snapshot :windows '(("editor" 1 1) ("shell" 4 1)))
                   (workspace-snapshot :windows '(("editor" 2 2) ("shell" 4 1)))
                   (workspace-snapshot :windows '(("editor" 1 2)))
                   (workspace-snapshot :windows '(("editor" 1 2) ("shell" 4 1)
                                                  ("extra" 5 1)))))
      (if (string= "other" (libtmux:name (aref (libtmux:sessions conflict) 0)))
          (is (plusp (length (workspace-call :plan-steps
                                             (workspace-call :plan-workspace workspace conflict)))))
          (signals-workspace :workspace-conflict
            (workspace-call :plan-workspace workspace conflict))))
    (is (zerop calls))))
