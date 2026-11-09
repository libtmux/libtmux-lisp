(in-package #:libtmux.tests)

(in-suite workspace-integration)

(defun state-geometry-window (state)
  (let ((geometry (getf (state-call :owned-state-data state) :geometry)))
    (when geometry (aref (getf geometry :windows) 0))))

(defun state-geometry-pane (state id)
  (let ((window (state-geometry-window state)))
    (when window
      (find id (getf window :panes) :key (lambda (pane) (getf pane :pane-id)) :test #'string=))))

(test owned-geometry-acquisition-retains-unzoomed-and-zoomed-observations
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (before (state-call :fetch-owned-state client declaration))
             (window (state-geometry-window before)))
        (is (not (null window)))
        (when window
          (is (eq t (getf window :regular-p)))
          (is (eq nil (getf window :zoomed-p :missing)))
          (fixture-ok fixture "split-window" "-d" "-t" "%0" "--" "/bin/cat")
          (fixture-ok fixture "resize-pane" "-Z" "-t" "%0")
          (let ((zoomed (state-geometry-window (state-call :fetch-owned-state client declaration))))
            (is (eq t (getf zoomed :zoomed-p)))
            (is (eq nil (getf zoomed :regular-p :missing))))
          (let ((libtmux.internal::*process-launched-hook*
                  (lambda (job) (declare (ignore job)) (error "Geometry inspection launched I/O"))))
            (is (eq t (getf (state-geometry-window before) :regular-p)))
            (setf (char (getf window :window-id) 0) #\X)
            (is (string= "@0" (getf (state-geometry-window before) :window-id)))))))))

(test owned-geometry-observes-floating-panes-without-granting-zoomed-permission
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (if (eq :legacy (state-call :owned-geometry-profile (libtmux:tmux-version client)))
          (skip "Floating panes require tmux 3.7 or newer")
          (let ((declaration (install-state-fixture fixture client)))
            (fixture-ok fixture "new-pane" "-d" "-t" "%0" "--" "/bin/cat")
            (let* ((state (state-call :fetch-owned-state client declaration))
                   (floating (state-geometry-pane state "%1")))
              (is (not (null floating)))
              (when floating
                (is (eq t (getf floating :floating-p)))
                (is (eq nil (getf (state-geometry-window state) :regular-p :missing)))))
            (fixture-ok fixture "split-window" "-d" "-t" "%0" "--" "/bin/cat")
            (fixture-ok fixture "resize-pane" "-Z" "-t" "%0")
            (let* ((state (state-call :fetch-owned-state client declaration))
                   (floating (state-geometry-pane state "%1"))
                   (window (state-geometry-window state)))
              (is (not (null floating)))
              (when window
                (is (eq t (getf window :zoomed-p)))
                (when (eq :modal (state-call :owned-geometry-profile (libtmux:tmux-version client)))
                  (is (eq nil (getf floating :floating-p :missing))))
                (is (eq nil (getf window :regular-p :missing))))))))))

(test owned-geometry-observes-modal-panes
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (if (not (eq :modal (state-call :owned-geometry-profile (libtmux:tmux-version client))))
          (skip "Modal panes require tmux 3.8")
          (let ((declaration (install-state-fixture fixture client)))
            (fixture-ok fixture "new-pane" "-O" "-d" "-t" "%0" "--" "/bin/cat")
            (let* ((state (state-call :fetch-owned-state client declaration))
                   (modal (state-geometry-pane state "%1")))
              (is (not (null modal)))
              (when modal
                (is (eq t (getf modal :modal-p)))
                (is (eq nil (getf (state-geometry-window state) :regular-p :missing))))))))))

(test owned-geometry-normalizes-linked-window-rows
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let ((declaration (install-state-fixture fixture client)))
        (fixture-ok fixture "link-window" "-s" "@0" "-t" "fixture:3")
        (let* ((state (state-call :fetch-owned-state client declaration))
               (window (state-geometry-window state)))
          (is (not (null window)))
          (when window
            (is (= 1 (length (getf window :panes))))
            (is (= 2 (length (libtmux:window-links (state-call :owned-state-snapshot state)))))))))))

(test regular-core-split-anchors-preserve-existing-pane-order
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((declaration (install-state-fixture fixture client))
             (state (state-call :fetch-owned-state client declaration))
             (panes (libtmux:panes (state-call :owned-state-snapshot state))))
        (is (eq t (getf (state-geometry-window state) :regular-p)))
        (dolist (spec '(("%0" nil :horizontal) ("%0" t :vertical)
                        ("%0" nil :horizontal) ("%1" nil :vertical)))
          (destructuring-bind (id before direction) spec
            (let* ((target (find id panes :key #'libtmux:id :test #'string=))
                   (outcome (libtmux:split-pane client target :before before :direction direction
                                                :command #("/bin/cat")))
                   (created (libtmux:outcome-value outcome)))
              (setf panes (libtmux:panes (libtmux:window created))))))
        (is (equal '("%2" "%0" "%3" "%1" "%4") (map 'list #'libtmux:id panes)))))))
