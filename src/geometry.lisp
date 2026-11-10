(in-package #:libtmux.internal)

(defun resize-arguments (width height direction amount amount-p zoom fit)
  (unless (= 1 (count-if #'identity (list (or width height) direction zoom fit)))
    (invalid-argument "Choose one resize mode: dimensions, direction, zoom, or fit"))
  (when (and amount-p (not direction))
    (invalid-argument "Amount requires a resize direction"))
  (cond
    (zoom '("-Z"))
    (fit (list (case fit (:smallest "-a") (:largest "-A")
                 (otherwise (invalid-argument "Fit must be :smallest or :largest")))))
    (direction
     (list (case direction (:left "-L") (:right "-R") (:up "-U") (:down "-D")
             (otherwise (invalid-argument "Direction must be :left, :right, :up or :down")))
           (integer-argument amount 1 2147483647 "Resize amount")))
    (t (append (when width (list "-x" (integer-argument width 1 10000 "Width")))
               (when height (list "-y" (integer-argument height 1 10000 "Height")))))))

(defun operate-on-target (client target model command flags observe options)
  (apply #'perform-command client (list target)
         (append (list command "-t" (physical-target target model)) flags)
         :observe (when observe (observe-target client target)) options))

(defun custom-layout-text (text)
  "Validate the layout header; leave checksum, JSON and geometry validation to tmux."
  (let* ((text (text-argument text "Custom layout" nil))
         (start (position-if-not (lambda (character) (find (char-code character) '(9 10 11 12 13 32))) text))
         (json-p (and start (char= (char text start) #\{))))
    ;; Tmux 3.3a leaves its error pointer unset when legacy header scanning fails.
    (unless (or json-p
                (and (> (length text) 5) (char= (char text 4) #\,)
                     (loop for index below 4 always (find (char text index) "0123456789abcdefABCDEF"))))
      (invalid-argument "Custom layout needs four ASCII hex digits, a comma and a body, or a JSON object"))
    (values text json-p)))

(defun layout-argument (layout)
  (let ((named (cdr (assoc layout '((:even-horizontal . "even-horizontal")
                                    (:even-vertical . "even-vertical")
                                    (:main-horizontal . "main-horizontal")
                                    (:main-vertical . "main-vertical") (:tiled . "tiled"))))))
    (when named (return-from layout-argument (values named nil)))
    (when (consp layout)
      (let ((parts (finite-vector layout "Custom layout")))
        (when (and (= 2 (length parts)) (eq :custom (aref parts 0)))
          (return-from layout-argument (custom-layout-text (aref parts 1))))))
    (invalid-argument "Layout must be a supported keyword or (:custom string)")))

(in-package #:libtmux)

(defun resize-pane (client pane &key width height direction (amount 1 amount-p) zoom
                                    (observe t) cancel-token timeout output-limit)
  "Resize PANE and return a COMMAND-OUTCOME with an optional replacement pane.
Choose cell WIDTH/HEIGHT (1..10000), a DIRECTION and positive AMOUNT, or ZOOM.
DIRECTION is :LEFT, :RIGHT, :UP or :DOWN; AMOUNT defaults to one. ZOOM toggles
the window's zoom state. Modes are exclusive. Tmux may clamp sizes to the
available layout; inspect the observed value. Earlier captures stay unchanged.
Signals INVALID-ARGUMENT, STALE-TARGET or an operational condition."
  (libtmux.internal::operate-on-target
   client pane :pane "resize-pane"
   (libtmux.internal::resize-arguments width height direction amount amount-p zoom nil)
   observe (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun resize-window (client window &key width height direction (amount 1 amount-p) fit
                                        (observe t) cancel-token timeout output-limit)
  "Resize physical WINDOW and return an outcome with an optional replacement.
Choose cell WIDTH/HEIGHT (1..10000), a DIRECTION and positive AMOUNT, or FIT
(:SMALLEST or :LARGEST attached client). Modes are exclusive; dimensions are
subject to tmux's layout constraints. A resize sets the window-size option to
manual, as tmux does. Signals INVALID-ARGUMENT, STALE-TARGET or an operational
condition. Observation failure is retained separately from mutation success."
  (libtmux.internal::operate-on-target
   client window :window "resize-window"
   (libtmux.internal::resize-arguments width height direction amount amount-p nil fit)
   observe (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun select-layout (client window layout &key (observe t) cancel-token timeout output-limit)
  "Apply LAYOUT to physical WINDOW; return an outcome and optional replacement.
LAYOUT is :EVEN-HORIZONTAL, :EVEN-VERTICAL, :MAIN-HORIZONTAL, :MAIN-VERTICAL,
:TILED, or (:CUSTOM string) containing a tmux layout description. Legacy custom
text requires four ASCII hex digits, a comma and a nonempty body; JSON-object
layouts require a live tmux daemon at least 3.8. Header checks precede I/O;
the existing target preflight checks the daemon version before dispatch.
Text is literal; tmux validates its checksum, JSON and geometry. This unzooms
the window. Signals INVALID-ARGUMENT, UNSUPPORTED-CAPABILITY, STALE-TARGET or
an operational condition. Does not change earlier captured values.

See also: NEXT-LAYOUT, PREVIOUS-LAYOUT, OUTCOME-VALUE."
  (multiple-value-bind (argument json-p) (libtmux.internal::layout-argument layout)
    (libtmux.internal::operate-on-target
     client window :window "select-layout" (list "--" argument) observe
     (append (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)
             (when json-p '(:minimum-version "3.8" :feature :json-layout))))))

(defun next-layout (client window &key (observe t) cancel-token timeout output-limit)
  "Cycle WINDOW to tmux's next layout; return an outcome and optional replacement.
Unzooms the window. Captured values remain unchanged. Signals STALE-TARGET or
an operational condition; follow-up acquisition failure is retained separately."
  (libtmux.internal::operate-on-target
   client window :window "next-layout" nil observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun previous-layout (client window &key (observe t) cancel-token timeout output-limit)
  "Cycle WINDOW to tmux's previous layout; return an outcome and optional replacement.
Unzooms the window. Captured values remain unchanged. Signals STALE-TARGET or
an operational condition; follow-up acquisition failure is retained separately."
  (libtmux.internal::operate-on-target
   client window :window "previous-layout" nil observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))
