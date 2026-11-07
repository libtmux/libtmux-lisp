(in-package #:libtmux.internal)

(defconstant +registry-version+ 1)

(defstruct (field-spec (:constructor make-field-spec (key model kind &key format optional
                                                         minimum maximum target cardinality)))
  key model kind format optional minimum maximum target cardinality)

(defparameter *field-registry* (make-hash-table :test 'eq))
(defparameter *format-registry* (make-hash-table :test 'equal))

(defun register-field (key model kind &key format optional minimum maximum target cardinality)
  (let ((field (make-field-spec key model kind :format format :optional optional
                                :minimum minimum :maximum maximum
                                :target target :cardinality cardinality)))
    (setf (gethash key *field-registry*) field)
    (when format (setf (gethash format *format-registry*) field))
    field))

(defun registered-field (key model)
  (let ((field (gethash key *field-registry*)))
    (unless (and field (eq model (field-spec-model field)))
      (error 'libtmux:field-unavailable :field key :model model
             :message (format nil "Field ~S is not registered for model ~S" key model)))
    field))

(defun model-fields (model)
  (sort (loop for field being the hash-values of *field-registry*
              when (eq model (field-spec-model field)) collect field)
        #'string< :key (lambda (field) (symbol-name (field-spec-key field)))))

;; Numeric envelopes describe tmux's Linux wire values, not Lisp query integers.
(dolist (entry '((:server/pid :server :integer "pid" 1 2147483647)
                 (:server/start-time :server :integer "start_time" -9223372036854775808 9223372036854775807)
                 (:session/created :session :integer "session_created" -9223372036854775808 9223372036854775807 t)
                 (:session/attached-count :session :integer "session_attached" 0 4294967295)
                 (:session/window-link-count :session :integer "session_windows" 0 4294967295)
                 (:link/index :window-link :integer "window_index" 0 2147483647)
                 (:window/width :window :integer "window_width" 1 4294967295)
                 (:window/height :window :integer "window_height" 1 4294967295)
                 (:window/pane-count :window :integer "window_panes" 0 4294967295)
                 (:pane/index :pane :integer "pane_index" 0 4294967295)
                 (:pane/width :pane :integer "pane_width" 1 4294967295)
                 (:pane/height :pane :integer "pane_height" 1 4294967295)
                 (:pane/pid :pane :integer "pane_pid" 1 2147483647 :zero)
                 (:client/pid :client :integer "client_pid" 1 2147483647)
                 (:client/created :client :integer "client_created" -9223372036854775808 9223372036854775807 t)))
  (destructuring-bind (key model kind format minimum maximum &optional optional) entry
    (register-field key model kind :format format :minimum minimum :maximum maximum :optional optional)))

(dolist (entry '((:server/socket-path :server "socket_path")
                 (:server/version :server "version")
                 (:session/id :session "session_id")
                 (:session/name :session "session_name")
                 (:window/id :window "window_id")
                 (:window/name :window "window_name")
                 (:window/layout :window "window_layout" t)
                 (:pane/id :pane "pane_id")
                 (:pane/current-command :pane "pane_current_command" t)
                 (:pane/current-path :pane "pane_current_path" t)
                 (:pane/title :pane "pane_title")
                 (:pane/start-command :pane "pane_start_command")
                 (:client/name :client "client_name")
                 (:client/tty :client "client_tty" t)))
  (destructuring-bind (key model format &optional optional) entry
    (register-field key model :text :format format :optional optional)))

(dolist (entry '((:link/active :window-link "window_active")
                 (:pane/active :pane "pane_active")
                 (:pane/dead :pane "pane_dead")
                 (:client/control-mode :client "client_control_mode")
                 (:client/read-only :client "client_readonly")))
  (destructuring-bind (key model format) entry
    (register-field key model :boolean :format format)))

(dolist (entry '((:session/window-links :session :window-link :many)
                 (:session/clients :session :client :many)
                 (:link/session :window-link :session :one)
                 (:link/window :window-link :window :one)
                 (:window/links :window :window-link :many)
                 (:window/panes :window :pane :many)
                 (:pane/window :pane :window :one)
                 (:client/session :client :session :one)))
  (destructuring-bind (key model target cardinality) entry
    (register-field key model :relation :target target :cardinality cardinality)))

(defun invalid-wire-value (field text)
  (error 'libtmux:decoding-error
         :message (format nil "Invalid ~A value for ~S: ~S"
                          (field-spec-kind field) (field-spec-key field)
                          (subseq text 0 (min 80 (length text))))))

(defun decimal-integer (text minimum maximum field)
  (let ((start (if (and (plusp (length text)) (char= (char text 0) #\-)) 1 0)))
    (unless (and (< start (length text)) (<= (length text) 20)
                 (or (zerop start) (minusp minimum))
                 (every (lambda (char) (char<= #\0 char #\9)) (subseq text start)))
      (invalid-wire-value field text))
    (let ((number (parse-integer text)))
      (unless (<= minimum number maximum) (invalid-wire-value field text))
      number)))

(defun decode-scalar (field text)
  (let ((key (field-spec-key field)))
    (when (and (field-spec-optional field)
               (or (zerop (length text))
                   (and (eq :zero (field-spec-optional field)) (equal text "0"))))
      (return-from decode-scalar (values nil nil)))
    (values
     (ecase (field-spec-kind field)
       (:boolean (cond ((equal text "1") t) ((equal text "0") nil)
                       (t (invalid-wire-value field text))))
       (:integer (decimal-integer text (field-spec-minimum field) (field-spec-maximum field) field))
       (:text
        (let ((prefix (case key (:session/id #\$) (:window/id #\@) (:pane/id #\%))))
          (when prefix
            (unless (and (> (length text) 1) (char= (char text 0) prefix))
              (invalid-wire-value field text))
            (decimal-integer (subseq text 1) 0 4294967295 field))
          (when (and (member key '(:server/socket-path :server/version :client/name))
                     (zerop (length text)))
            (invalid-wire-value field text)))
        (copy-seq text)))
     t)))
