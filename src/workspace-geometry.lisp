(in-package #:libtmux.workspace)

(defun owned-geometry-profile (version)
  "Select the exact source-qualified geometry formats; absent features use literal false."
  (unless (stringp version) (fail-workspace "Workspace geometry needs an exact tmux version"))
  (cond
    ((member version '("3.3a" "3.4" "3.5" "3.5a" "3.6" "3.6a" "3.6b") :test #'string=) :legacy)
    ((member version '("3.7" "3.7a" "3.7b" "3.7c") :test #'string=) :floating)
    ((string= version "3.8") :modal)
    (t (fail-workspace "No qualified workspace geometry profile for this tmux version"))))

(defun owned-geometry-format (version)
  (let ((profile (owned-geometry-profile version)))
    (format nil "workspace-geometry/1~C#{window_id}~C#{window_zoomed_flag}~C#{pane_id}~C~A~C~A"
            #\Tab #\Tab #\Tab #\Tab
            (if (eq profile :legacy) "0" "#{pane_floating_flag}") #\Tab
            (if (eq profile :modal) "#{pane_modal_flag}" "0"))))

(defun geometry-boolean (text)
  (cond ((string= text "0") nil) ((string= text "1") t)
        (t (fail-workspace "Geometry facts require present 0 or 1 flags" :path #(:geometry)))))

(defun parse-owned-geometry (text snapshot version &key check-row)
  "Return complete owned geometry facts; zoomed false floating flags grant no permission."
  (let* ((profile (owned-geometry-profile version))
         (windows (libtmux:windows snapshot))
         (expected (make-hash-table :test #'equal))
         (facts (make-hash-table :test #'equal))
         (zoom (make-hash-table :test #'equal)))
    (unless (and (stringp text) (not (find #\Null text))
                 (or (zerop (length text)) (char= #\Newline (char text (1- (length text))))))
      (fail-workspace "Geometry facts are not complete native rows" :path #(:geometry)))
    (loop for window across windows
          for id = (libtmux:id window)
          do (loop for pane across (libtmux:panes window)
                   do (setf (gethash (libtmux:id pane) expected) id)))
    (loop for start = 0 then (1+ end)
          for end = (position #\Newline text :start start)
          while end
          do (when check-row (funcall check-row))
             (let ((parts (uiop:split-string (subseq text start end) :separator '(#\Tab))))
               (unless (and (= 6 (length parts)) (string= (first parts) "workspace-geometry/1"))
                 (fail-workspace "Unknown or malformed geometry row" :path #(:geometry)))
               (destructuring-bind (tag window zoom-text pane floating-text modal-text) parts
                 (declare (ignore tag))
                 (unless (equal window (gethash pane expected))
                   (fail-workspace "Geometry pane is missing or belongs to another captured window"
                                   :path #(:geometry)))
                 (let* ((zoomed (geometry-boolean zoom-text))
                        (floating (geometry-boolean floating-text))
                        (modal (geometry-boolean modal-text))
                        (value (list window zoomed floating modal)))
                   (when (or (and (eq profile :legacy) floating)
                             (and (not (eq profile :modal)) modal))
                     (fail-workspace "Geometry row claims an unsupported feature" :path #(:geometry)))
                   (multiple-value-bind (previous present-p) (gethash pane facts)
                     (when (and present-p (not (equal value previous)))
                       (fail-workspace "Contextual geometry rows disagree" :path #(:geometry))))
                   (multiple-value-bind (previous present-p) (gethash window zoom)
                     (when (and present-p (not (eq zoomed previous)))
                       (fail-workspace "Window zoom changed between geometry rows" :path #(:geometry))))
                   (setf (gethash pane facts) value (gethash window zoom) zoomed)))))
    (unless (and (= (hash-table-count facts) (hash-table-count expected))
                 (= (hash-table-count zoom) (length windows)))
      (fail-workspace "Geometry rows do not cover the complete captured graph" :path #(:geometry)))
    (list :version (copy-seq version)
          :windows
          (map 'simple-vector
               (lambda (window)
                 (let* ((id (libtmux:id window))
                        (panes
                          (map 'simple-vector
                               (lambda (pane)
                                 (let* ((id (libtmux:id pane)) (value (gethash id facts)))
                                   (list :pane-id id :floating-p (third value) :modal-p (fourth value))))
                               (libtmux:panes window)))
                        (zoomed (gethash id zoom)))
                   (list :window-id id :zoomed-p zoomed :panes panes
                         :regular-p (and (not zoomed)
                                         (every (lambda (pane)
                                                  (not (or (getf pane :floating-p) (getf pane :modal-p))))
                                                panes)))))
               windows))))
