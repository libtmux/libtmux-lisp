(in-package #:libtmux.tests)

(in-suite workspace)

(defun geometry-row (window pane zoom floating modal)
  (format nil "workspace-geometry/1~C~A~C~A~C~A~C~A~C~A~%"
          #\Tab window #\Tab zoom #\Tab pane #\Tab floating #\Tab modal))

(defun geometry-text (&key (zoom "0") (floating "0") (modal "0"))
  (concatenate 'string (geometry-row "@10" "%20" zoom floating modal)
               (geometry-row "@11" "%21" "0" "0" "0")
               (geometry-row "@12" "%22" "0" "0" "0")))

(test owned-geometry-uses-exact-source-profiles
  (is (eq :legacy (workspace-call :owned-geometry-profile "3.3a")))
  (is (eq :legacy (workspace-call :owned-geometry-profile "3.6b")))
  (is (eq :floating (workspace-call :owned-geometry-profile "3.7")))
  (is (eq :floating (workspace-call :owned-geometry-profile "3.7c")))
  (is (eq :modal (workspace-call :owned-geometry-profile "3.8")))
  (signals libtmux.workspace:workspace-error (workspace-call :owned-geometry-profile "unknown")))

(test owned-geometry-requires-unzoomed-regular-facts
  (let* ((snapshot (owned-state-graph))
         (libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (error "Local geometry parsing launched I/O"))))
    (dolist (version '("3.3a" "3.7" "3.8"))
      (let* ((facts (workspace-call :parse-owned-geometry (geometry-text) snapshot version))
             (windows (getf facts :windows)))
        (is (= 3 (length windows)))
        (is-true (getf (aref windows 0) :regular-p))
        (is (not (getf (aref (getf (aref windows 0) :panes) 0) :floating-p)))))
    (dolist (text (list (geometry-text :floating "1")
                       (geometry-text :zoom "1")
                       (geometry-text :floating "1" :modal "1")))
      (let ((window (aref (getf (workspace-call :parse-owned-geometry text snapshot "3.8") :windows) 0)))
        (is (not (getf window :regular-p)))))
    (let* ((text (geometry-text))
           (facts (workspace-call :parse-owned-geometry text snapshot "3.8")))
      (setf (char (getf (aref (getf facts :windows) 0) :window-id) 0) #\X)
      (is (string= "@10" (getf (aref (getf (workspace-call :parse-owned-geometry text snapshot "3.8") :windows) 0)
                                :window-id))))))

(test owned-geometry-rejects-incomplete-contradictory-and-unsupported-facts
  (let ((snapshot (owned-state-graph)))
    (dolist (text (list "" (subseq (geometry-text) 0 (1- (length (geometry-text))))
                       (geometry-text :floating "") (geometry-text :modal "false")
                       (concatenate 'string (geometry-text) (geometry-row "@10" "%20" "1" "0" "0"))
                       (concatenate 'string (geometry-row "@11" "%20" "0" "0" "0")
                                    (geometry-row "@11" "%21" "0" "0" "0")
                                    (geometry-row "@12" "%22" "0" "0" "0"))))
      (signals libtmux.workspace:workspace-error
        (workspace-call :parse-owned-geometry text snapshot "3.8")))
    (signals libtmux.workspace:workspace-error
      (workspace-call :parse-owned-geometry (geometry-text :floating "1") snapshot "3.6b"))
    (signals libtmux.workspace:workspace-error
      (workspace-call :parse-owned-geometry (geometry-text :modal "1") snapshot "3.7c"))
    (is (= 3 (length (getf (workspace-call :parse-owned-geometry
                                          (concatenate 'string (geometry-text)
                                                       (geometry-row "@10" "%20" "0" "0" "0"))
                                          snapshot "3.8") :windows))))))

(test owned-geometry-remains-associated-with-its-captured-graph
  (let* ((before (owned-state-graph)) (after (owned-state-graph))
         (geometry (workspace-call :parse-owned-geometry (geometry-text) before "3.8"))
         (groups #(("$8")))
         (reader (libtmux.workspace::make-owned-reader
                  :core (libtmux.internal::make-configuration-reader)
                  :snapshot before :geometry geometry :groups groups))
         (capture (symbol-function 'libtmux.internal::capture-with-retries))
         (check (symbol-function 'libtmux.workspace::owned-reader-check))
         (capture-fails t))
    (unwind-protect
         (progn
           (setf (symbol-function 'libtmux.internal::capture-with-retries)
                 (lambda (&rest arguments)
                   (declare (ignore arguments))
                   (if capture-fails (error "Injected capture failure") after))
                 (symbol-function 'libtmux.workspace::owned-reader-check)
                 (lambda (reader) (declare (ignore reader)) (error "Injected post-capture failure")))
           (signals error (workspace-call :owned-read-graph reader))
           (is (eq before (libtmux.workspace::owned-reader-snapshot reader)))
           (is (eq geometry (libtmux.workspace::owned-reader-geometry reader)))
           (setf capture-fails nil)
           (signals error (workspace-call :owned-read-graph reader))
           (is (eq after (libtmux.workspace::owned-reader-snapshot reader)))
           (is (null (libtmux.workspace::owned-reader-geometry reader)))
           (is (null (libtmux.workspace::owned-reader-groups reader))))
      (setf (symbol-function 'libtmux.internal::capture-with-retries) capture
            (symbol-function 'libtmux.workspace::owned-reader-check) check))))

(test owned-geometry-failed-reread-does-not-retain-earlier-permission
  (let* ((snapshot (owned-state-graph))
         (reader (libtmux.workspace::make-owned-reader
                  :witness (libtmux.internal::make-server-witness :version "3.8")
                  :snapshot snapshot
                  :geometry (workspace-call :parse-owned-geometry (geometry-text) snapshot "3.8")))
         (read-text (symbol-function 'libtmux.workspace::owned-read-text)))
    (unwind-protect
         (progn
           (setf (symbol-function 'libtmux.workspace::owned-read-text)
                 (lambda (&rest arguments)
                   (declare (ignore arguments)) (error "Injected geometry read failure")))
           (signals error (workspace-call :owned-read-geometry reader snapshot))
           (is (eq snapshot (libtmux.workspace::owned-reader-snapshot reader)))
           (is (null (libtmux.workspace::owned-reader-geometry reader))))
      (setf (symbol-function 'libtmux.workspace::owned-read-text) read-text))))
