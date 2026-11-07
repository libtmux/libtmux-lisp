(in-package #:libtmux.tests)

(in-suite integration)

(test geometry-and-selection-preserve-captured-state
  (with-tmux-fixture (fixture)
    (with-fixture-client (client fixture)
      (let* ((session (aref (libtmux:fetch-sessions client) 0))
             (window (aref (libtmux:windows session) 0))
             (old-width (libtmux:width window))
             (resized (libtmux:outcome-value
                       (libtmux:resize-window client window :width 120 :height 40))))
        (is (= 120 (libtmux:width resized)))
        (is (= 40 (libtmux:height resized)))
        (is (= old-width (libtmux:width window)))
        (let* ((original (aref (libtmux:panes resized) 0))
               (second (libtmux:outcome-value
                        (libtmux:split-pane client original :direction :horizontal
                                           :command '("/bin/cat"))))
               (vertical (libtmux:outcome-value
                          (libtmux:select-layout client window :even-vertical)))
               (layout (libtmux:field-value vertical :window/layout))
               (height (libtmux:height (aref (libtmux:panes vertical) 0)))
               (shorter (libtmux:outcome-value (libtmux:resize-pane client original :height 8))))
          (is (every (lambda (pane) (= 120 (libtmux:width pane))) (libtmux:panes vertical)))
          (is (= 8 (libtmux:height shorter)))
          (is (= height (libtmux:height (aref (libtmux:panes vertical) 0))))
          (libtmux:select-pane client second :observe nil)
          (is (libtmux:same-entity-p original (libtmux:outcome-value (libtmux:last-pane client window))))
          (libtmux:next-layout client window :observe nil)
          (let ((back (libtmux:outcome-value (libtmux:previous-layout client window))))
            (is (every (lambda (pane) (= 120 (libtmux:width pane))) (libtmux:panes back))))
          (let ((restored (libtmux:outcome-value
                           (libtmux:select-layout client window (list :custom layout)))))
            (is (string= layout (libtmux:field-value restored :window/layout)))))
        (let* ((other (libtmux:outcome-value (libtmux:new-window client session :command '("/bin/cat"))))
               (next (libtmux:outcome-value (libtmux:next-window client session)))
               (previous (libtmux:outcome-value (libtmux:previous-window client session)))
               (last (libtmux:outcome-value (libtmux:last-window client session))))
          (is (typep next 'libtmux:window-link))
          (is (libtmux:same-entity-p other (libtmux:window next)))
          (is (libtmux:same-entity-p window (libtmux:window previous)))
          (is (libtmux:same-entity-p other (libtmux:window last)))
          (is (libtmux:same-entity-p session (libtmux:session last))))
        (let ((calls 0))
          (let ((libtmux.internal::*process-started-hook*
                  (lambda (process) (declare (ignore process)) (incf calls))))
            (signals libtmux:invalid-argument
              (libtmux:resize-window client window :width 120 :fit :largest))
            (signals libtmux:invalid-argument
              (libtmux:resize-pane client (aref (libtmux:panes window) 0) :width 1/2))
            (signals libtmux:invalid-argument
              (libtmux:resize-pane client (aref (libtmux:panes window) 0) :width 10001))
            (signals libtmux:invalid-argument
              (libtmux:select-layout client window "even-horizontal"))
            (is (zerop calls))))))))
