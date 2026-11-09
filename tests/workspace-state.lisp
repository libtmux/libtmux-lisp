(in-package #:libtmux.tests)

(in-suite workspace)

(defun owned-state-graph (&key wrong-link missing-pane swapped-panes extra-pane shared)
  (let ((index (if wrong-link "2" "1")))
    (libtmux.internal::build-snapshot
     (gensym "OWNED-STATE-") 1
     '(:server/pid 7 :server/start-time 10 :server/process-start 20
       :server/socket-device 1 :server/socket-inode 2 :server/version "3.8")
     (synthetic-rows :session (list (list "session/1" "$8" "renamed" "1" "0" (if shared "4" "3"))))
     (synthetic-rows :window-link
       (append
       (list (list "window-link/1" "$8" index "@10" "drifted" "120" "30" (if extra-pane "2" "1") "1" "changed")
             '("window-link/1" "$8" "4" "@11" "same" "120" "30" "1" "0" "changed")
             '("window-link/1" "$8" "7" "@12" "unmanaged" "120" "30" "1" "0" "other"))
       (when shared
         (list (list "window-link/1" "$8" "9" "@10" "drifted" "120" "30" (if extra-pane "2" "1") "0" "changed")))))
     (synthetic-rows :pane
       (append
       (list (list "pane/1" "$8" index "@10"
                   (cond (missing-pane "%2523") (swapped-panes "%2521") (t "%2520"))
                   "0" "1" "120" "30" "cat" "/" "" "100" "0" "cat")
             (list "pane/1" "$8" "4" "@11" (if swapped-panes "%2520" "%2521")
                   "0" "1" "120" "30" "cat" "/" "" "100" "0" "cat")
             '("pane/1" "$8" "7" "@12" "%2522" "0" "1" "120" "30" "cat" "/" "" "100" "0" "cat"))
       (when extra-pane (list (list "pane/1" "$8" index "@10" "%2523" "1" "0" "60" "30" "cat" "/" "" "100" "0" "cat")))
       (when shared
         (append (list '("pane/1" "$8" "9" "@10" "%2520" "0" "1" "120" "30" "cat" "/" "" "100" "0" "cat"))
                 (when extra-pane (list '("pane/1" "$8" "9" "@10" "%2523" "1" "0" "60" "30" "cat" "/" "" "100" "0" "cat")))))))
     #())))

(test owned-state-group-facts-distinguish-false-and-require-complete-coverage
  (let* ((snapshot (owned-state-graph))
         (text (format nil "workspace-group/1~C$8~C0~%" #\Tab #\Tab))
         (facts (workspace-call :parse-owned-groups text snapshot)))
    (is (equalp #(("$8")) facts))
    (is (equalp #(("$8" . t))
                (workspace-call :parse-owned-groups
                                (format nil "workspace-group/1~C$8~C1~%" #\Tab #\Tab) snapshot)))
    (dolist (bad (list "" (concatenate 'string text text)
                      (format nil "workspace-group/1~C$9~C0~%" #\Tab #\Tab)
                      (format nil "workspace-group/1~C$8~Cfalse~%" #\Tab #\Tab)))
      (signals-workspace :invalid-workspace
        (workspace-call :parse-owned-groups bad snapshot)))))

(test owned-state-graph-preserves-property-drift-but-refuses-identity-loss
  (let* ((record (workspace-call :make-owned-record :committed (owned-committed-data)))
         (snapshot (owned-state-graph))
         (libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (error "Local state validation launched a process"))))
    (is-true (workspace-call :validate-owned-graph record snapshot))
    (is (= 3 (length (libtmux:windows snapshot))))
    (dolist (bad (list (owned-state-graph :wrong-link t)
                      (owned-state-graph :missing-pane t)
                      (owned-state-graph :swapped-panes t)))
      (signals-workspace :workspace-conflict
        (workspace-call :validate-owned-graph record bad)))
    (let ((data (owned-committed-data)))
      (setf (getf (getf data :daemon) :pid) 99)
      (signals-workspace :workspace-conflict
        (workspace-call :validate-owned-graph
                        (workspace-call :make-owned-record :committed data) snapshot)))))
