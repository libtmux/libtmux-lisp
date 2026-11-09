(in-package #:libtmux.workspace)

(defconstant +owned-record-bytes+ 1048576)
(defconstant +owned-record-nodes+ 65536)
(defconstant +owned-text-length+ 65536)
(defconstant +owned-chunk-bytes+ 2048)

(defstruct (owned-context (:constructor make-owned-context (mode)))
  mode (nodes 0) (text-bytes 0) (windows 0) (panes 0)
  (window-ids (make-hash-table :test #'equal))
  (pane-ids (make-hash-table :test #'equal))
  (indexes (make-hash-table :test #'eql)))

(defclass owned-declaration ()
  ((data :initarg :data) (json :initarg :json))
  (:documentation "Private owned workspace/2 data; never an operational handle."))

;; Native key, wire name, validator, required flag and optional encoder.
(defparameter *owned-pane-fields*
  '((:id "id" owned-logical-id t)
    (:cwd "cwd" owned-nonempty-string nil)
    (:command "command" owned-command nil)
    (:shell-command "shell_command" owned-nonempty-string nil)))
(defparameter *owned-window-fields*
  '((:id "id" owned-logical-id t) (:name "name" owned-window-name t)
    (:index "index" owned-index nil) (:cwd "cwd" owned-nonempty-string nil)
    (:layout "layout" owned-layout nil encode-owned-layout)
    (:panes "panes" owned-pane-array t encode-owned-panes)))
(defparameter *owned-session-fields*
  '((:id "id" owned-logical-id t) (:name "name" owned-session-name t)
    (:cwd "cwd" owned-nonempty-string nil)
    (:environment "environment" owned-environment nil encode-owned-environment)
    (:windows "windows" owned-window-array t encode-owned-windows)))
(defparameter *owned-declaration-fields*
  '((:schema "schema" owned-string t) (:id "id" owned-logical-id t)
    (:session "session" owned-session-value t encode-owned-session)))

(defun owned-node (context path)
  (when (> (incf (owned-context-nodes context)) +owned-record-nodes+)
    (fail-workspace "Owned workspace exceeds its node bound"
                    :path path :limit :max-nodes)))

(defun owned-string (value path context)
  (owned-node context path)
  (unless (and (stringp value) (<= (length value) +owned-text-length+))
    (fail-workspace "Owned text must be a string of at most 65536 characters" :path path))
  (incf (owned-context-text-bytes context)
        (bounded-utf-8-size value (- +owned-record-bytes+ (owned-context-text-bytes context))))
  (owned-text value path "Owned text" :empty-p t))

(defun owned-nonempty-string (value path context)
  (let ((text (owned-string value path context)))
    (when (zerop (length text)) (fail-workspace "Owned text cannot be empty" :path path))
    text))

(defun owned-logical-id (value path context)
  (unless (and (stringp value) (<= 1 (length value) 64)
               (or (libtmux.internal::ascii-letter-p (char value 0))
                   (libtmux.internal::ascii-digit-p (char value 0)))
               (every (lambda (character)
                        (or (libtmux.internal::ascii-letter-p character)
                            (libtmux.internal::ascii-digit-p character)
                            (find character "_.-"))) value))
    (fail-workspace "Logical ID must match [A-Za-z0-9][A-Za-z0-9_.-]{0,63}" :path path))
  (owned-string value path context))

(defun owned-unique (value table path description)
  (when (gethash value table)
    (fail-workspace (format nil "Duplicate ~A" description) :path path))
  (setf (gethash value table) t)
  value)

(defun owned-integer (value minimum maximum path context)
  (owned-node context path)
  ;; JSON lexical validation excludes fractions; Jzon represents integer -0 as a float.
  (when (and (eq :json (owned-context-mode context)) (floatp value) (zerop value))
    (setf value 0))
  (unless (and (integerp value) (<= minimum value maximum))
    (fail-workspace (format nil "Expected an integer from ~D through ~D" minimum maximum)
                    :path path))
  value)

(defun owned-index (value path context)
  (owned-integer value 0 2147483647 path context))

(defun owned-member (object field context)
  (if (eq :json (owned-context-mode context))
      (object-member object (second field))
      (plist-value object (first field))))

(defun normalize-owned-object (object fields path context &optional schema)
  "Validate a closed object through trusted field converters, returning owned plists."
  (owned-node context path)
  (let ((json-p (eq :json (owned-context-mode context))))
    (if json-p
        (closed-object object (mapcar #'second fields) path "Owned workspace object")
        (closed-plist object (mapcar #'first fields) path "Owned workspace object"))
    (when schema
      (multiple-value-bind (value present-p) (owned-member object (first fields) context)
        (unless (and present-p (stringp value) (string= value schema))
          (fail-workspace "Unknown or missing owned workspace schema" :path (path+ path :schema)))))
    (loop for field in fields
          append (multiple-value-bind (value present-p) (owned-member object field context)
                   (let ((member-path (path+ path (if json-p (second field) (first field)))))
                     (when (and (fourth field) (not present-p))
                       (fail-workspace "A required owned workspace member is missing"
                                       :path member-path))
                     (when present-p
                       (list (first field) (funcall (third field) value member-path context))))))))

(defun owned-sequence (value path context minimum maximum)
  (owned-node context path)
  (let ((items (if (eq :json (owned-context-mode context))
                   (json-array value path "Owned sequence")
                   (finite-sequence value path "Owned sequence"))))
    (unless (<= minimum (length items) maximum)
      (fail-workspace (format nil "Expected ~D through ~D items" minimum maximum) :path path))
    items))

(defun owned-array (value path context minimum maximum converter)
  (let ((items (owned-sequence value path context minimum maximum)))
    (loop with result = (make-array (length items))
          for item across items for index from 0
          do (setf (aref result index) (funcall converter item (path+ path index) context))
          finally (return result))))

(defun owned-command (value path context)
  (let ((items (owned-sequence value path context 1 256)))
    (map 'simple-vector (lambda (item) (owned-string item path context))
         (normalized-command items path 256))))

(defun owned-environment (value path context)
  (owned-node context path)
  (let ((entries (normalized-environment
                  (if (eq :json (owned-context-mode context))
                      (wire-environment value path 256) value) path 256)))
    (sort (map 'simple-vector
               (lambda (entry)
                 (cons (owned-string (car entry) path context)
                       (owned-string (cdr entry) path context))) entries)
          #'string< :key #'car)))

(defun owned-layout (value path context)
  (let ((layout (normalized-layout
                 (if (eq :json (owned-context-mode context)) (wire-layout value path) value) path)))
    (if (keywordp layout)
        (progn (owned-node context path) layout)
        (progn (owned-node context path)
               (list :custom (owned-nonempty-string (second layout) path context))))))

(defun owned-session-name (value path context)
  (owned-tmux-name (owned-string value path context) path "Session name" :session-p t))

(defun owned-window-name (value path context)
  (owned-tmux-name (owned-string value path context) path "Window name"))

(defun owned-pane-value (value path context)
  (when (> (incf (owned-context-panes context)) 1000)
    (fail-workspace "Owned workspace exceeds 1000 panes" :path path :limit :max-panes))
  (let ((data (normalize-owned-object value *owned-pane-fields* path context)))
    (owned-unique (getf data :id) (owned-context-pane-ids context)
                  (path+ path (if (eq :json (owned-context-mode context)) "id" :id))
                  "pane logical ID")
    (when (and (nth-value 1 (plist-value data :command))
               (nth-value 1 (plist-value data :shell-command)))
      (fail-workspace "Specify argv or shell source, not both" :path path))
    data))

(defun owned-pane-array (value path context)
  (owned-array value path context 1 1000 #'owned-pane-value))

(defun owned-window-value (value path context)
  (when (> (incf (owned-context-windows context)) 100)
    (fail-workspace "Owned workspace exceeds 100 windows" :path path :limit :max-windows))
  (let ((data (normalize-owned-object value *owned-window-fields* path context)))
    (owned-unique (getf data :id) (owned-context-window-ids context)
                  (path+ path (if (eq :json (owned-context-mode context)) "id" :id))
                  "window logical ID")
    (multiple-value-bind (index present-p) (plist-value data :index)
      (when present-p
        (owned-unique index (owned-context-indexes context)
                      (path+ path (if (eq :json (owned-context-mode context)) "index" :index))
                      "window index")))
    data))

(defun owned-window-array (value path context)
  (owned-array value path context 1 100 #'owned-window-value))

(defun owned-session-value (value path context)
  (normalize-owned-object value *owned-session-fields* path context))

(defun owned-wire-object (data fields)
  (make-json-object
   (loop for field in fields
         append (multiple-value-bind (value present-p) (plist-value data (first field))
                  (when present-p
                    (list (cons (second field)
                                (if (fifth field) (funcall (fifth field) value) value))))))))

(defun encode-owned-layout (layout)
  (if (keywordp layout) (string-downcase (symbol-name layout))
      (make-json-object (list (cons "custom" (second layout))))))
(defun encode-owned-environment (entries)
  (make-json-object (coerce entries 'list)))
(defun encode-owned-panes (items)
  (map 'simple-vector (lambda (item) (owned-wire-object item *owned-pane-fields*)) items))
(defun encode-owned-windows (items)
  (map 'simple-vector (lambda (item) (owned-wire-object item *owned-window-fields*)) items))
(defun encode-owned-session (data)
  (owned-wire-object data *owned-session-fields*))

(defun owned-json (value)
  "Encode a normalized finite tree in canonical member order, without I/O."
  (let ((text
          (with-output-to-string (stream)
            (com.inuoe.jzon:with-writer (writer :stream stream :max-depth 32)
              (labels ((emit (value)
                         (typecase value
                           (json-object
                            (com.inuoe.jzon:with-object writer
                              (dolist (entry (json-object-entries value))
                                (com.inuoe.jzon:write-key writer (car entry))
                                (emit (cdr entry)))))
                           (string (com.inuoe.jzon:write-value writer value))
                           (vector (com.inuoe.jzon:with-array writer (map nil #'emit value)))
                           (integer (com.inuoe.jzon:write-value writer value))
                           (symbol (if (eq value 'null)
                                       (com.inuoe.jzon:write-value writer value)
                                       (fail-workspace "Unexpected canonical scalar")))
                           (t (fail-workspace "Unexpected canonical value")))))
                (emit value))))))
    (bounded-utf-8-size text +owned-record-bytes+)
    text))

(defun normalize-owned-declaration (data context &optional (path #()))
  (normalize-owned-object data *owned-declaration-fields* path context
                          "libtmux.lisp.workspace/2"))

(defun make-owned-declaration (data)
  "Return private owned workspace/2 data. No acquisition or application occurs."
  (let ((normalized (normalize-owned-declaration data (make-owned-context :native))))
    (make-instance 'owned-declaration :data normalized
                   :json (owned-json (owned-wire-object normalized *owned-declaration-fields*)))))

(defun owned-declaration-data (declaration)
  (deep-copy (slot-value declaration 'data)))

(defun owned-declaration-json (declaration)
  (copy-seq (slot-value declaration 'json)))

(defun parse-owned-tree (source)
  (unless (stringp source) (fail-document "Owned record must be a complete JSON string"))
  (bounded-utf-8-size source +owned-record-bytes+)
  (validate-json-integers source 32)
  (parse-json-events source 32 +owned-record-nodes+ +owned-text-length+))

(defun parse-owned-declaration (source)
  (handler-case
      (let ((data (normalize-owned-declaration (parse-owned-tree source)
                                             (make-owned-context :json))))
        (make-instance 'owned-declaration :data data
                       :json (owned-json (owned-wire-object data *owned-declaration-fields*))))
    (invalid-workspace-document (condition) (error condition))
    (invalid-workspace (condition)
      (fail-document "Owned declaration violates its schema" :cause condition))))

(defun owned-token (value path context)
  (unless (and (stringp value) (= 32 (length value))
               (every (lambda (character) (find character "0123456789ABCDEF")) value))
    (fail-workspace "Revision must contain exactly 32 uppercase hexadecimal digits" :path path))
  (owned-string value path context))

(defun owned-head (value path context)
  (if (equal value "0") (owned-string value path context) (owned-token value path context)))

(defun make-owned-control (state head &optional writer)
  "Return one canonical private control value, without accessing tmux."
  (let* ((context (make-owned-context :native))
         (head (owned-head head #(:head) context)))
    (case state
      (:idle
       (when (or (string= head "0") writer)
         (fail-workspace "Idle control requires a committed head and no writer"))
       (concatenate 'string "W2I." head))
      (:busy
       (let ((writer (owned-token writer #(:writer) context)))
         (when (string= head writer) (fail-workspace "Writer token must differ from the base head"))
         (concatenate 'string "W2B." head "." writer)))
      (otherwise (fail-workspace "Control state must be :IDLE or :BUSY")))))

(defun parse-owned-control (text)
  "Decode one closed control value into fresh inert data, without I/O."
  (unless (and (stringp text) (<= 36 (length text) 69))
    (fail-workspace "Control must be a bounded canonical string"))
  (let* ((parts (uiop:split-string text :separator "."))
         (state (cond ((and (= 2 (length parts)) (string= "W2I" (first parts))) :idle)
                      ((and (= 3 (length parts)) (string= "W2B" (first parts))) :busy)
                      (t (fail-workspace "Unknown owned workspace control syntax"))))
         (value (make-owned-control state (second parts) (third parts))))
    (unless (string= text value) (fail-workspace "Noncanonical owned control value"))
    (append (list :state state :head (copy-seq (second parts)))
            (when (eq state :busy) (list :writer (copy-seq (third parts)))))))

(defun owned-namespace (id)
  "Return a collision-free reserved prefix for one logical workspace ID."
  (let ((id (owned-logical-id id #(:id) (make-owned-context :native))))
    (with-output-to-string (stream)
      (write-string "@libtmux.workspace." stream)
      (loop for byte across (libtmux.internal::encode-utf8 id)
            do (format stream "~2,'0X" byte))
      (write-char #\. stream))))

(defun owned-kind-name (kind)
  (case kind (:pending "pending") (:committed "committed")
        (otherwise (fail-workspace "Record kind must be :PENDING or :COMMITTED"))))

(defun owned-kind (value path context)
  (owned-node context path)
  (if (eq :json (owned-context-mode context))
      (cond ((equal value "pending") :pending) ((equal value "committed") :committed)
            (t (fail-workspace "Unknown record kind" :path path)))
      (progn (owned-kind-name value) value)))

(defun owned-record-key (id kind revision &optional index)
  "Derive one descriptor or chunk key; no serialized option name is executed."
  (let ((prefix (owned-namespace id))
        (revision (owned-token revision #(:revision) (make-owned-context :native)))
        (kind (owned-kind-name kind)))
    (when index (owned-integer index 0 511 #(:index) (make-owned-context :native)))
    (format nil "~A~A.~A.~A" prefix kind revision
            (if index (format nil "chunk.~D" index) "descriptor"))))

(defun owned-byte-count (value path context)
  (owned-integer value 1 +owned-record-bytes+ path context))
(defun owned-chunk-count (value path context)
  (owned-integer value 1 512 path context))

(defparameter *owned-descriptor-fields*
  '((:schema "schema" owned-string t) (:kind "kind" owned-kind t owned-kind-name)
    (:revision "revision" owned-token t) (:bytes "bytes" owned-byte-count t)
    (:chunks "chunks" owned-chunk-count t)))

(defun normalize-owned-descriptor (data context)
  (let ((data (normalize-owned-object data *owned-descriptor-fields* #() context
                                      "libtmux.lisp.workspace.record/1")))
    (unless (= (getf data :chunks) (ceiling (getf data :bytes) +owned-chunk-bytes+))
      (fail-workspace "Descriptor chunk count disagrees with its byte count" :path #(:chunks)))
    data))

(defun encode-owned-envelope (kind revision text)
  "Return descriptor JSON and owned hex chunks; payload schema validation is separate."
  (let* ((context (make-owned-context :native))
         (revision (owned-token revision #(:revision) context))
         (text (owned-text text #() "Record text"))
         (size (bounded-utf-8-size text +owned-record-bytes+))
         (bytes (libtmux.internal::encode-utf8 text))
         (count (ceiling size +owned-chunk-bytes+))
         (descriptor
           (normalize-owned-descriptor
            (list :schema "libtmux.lisp.workspace.record/1" :kind kind
                  :revision revision :bytes size :chunks count) context))
         (chunks (make-array count)))
    (loop for index below count
          for start = (* index +owned-chunk-bytes+)
          do (setf (aref chunks index)
                   (with-output-to-string (stream)
                     (loop for offset from start below (min size (+ start +owned-chunk-bytes+))
                           do (format stream "~2,'0X" (aref bytes offset))))))
    (values (owned-json (owned-wire-object descriptor *owned-descriptor-fields*)) chunks)))

(defun decode-owned-envelope (kind revision descriptor chunks)
  "Decode a complete selected frame to fresh UTF-8 text, without granting authority."
  (let* ((context (make-owned-context :json))
         (data (normalize-owned-descriptor (parse-owned-tree descriptor) context))
         (chunks (finite-sequence chunks #(:chunks) "Record chunks"))
         (size (getf data :bytes)))
    (owned-kind-name kind)
    (owned-token revision #(:revision) (make-owned-context :native))
    (unless (and (eq kind (getf data :kind)) (string= revision (getf data :revision))
                 (= (length chunks) (getf data :chunks)))
      (fail-document "Descriptor does not match the selected record frame"))
    (let ((bytes (make-array size :element-type '(unsigned-byte 8))))
      (loop for chunk across chunks for index from 0
            for start = (* index +owned-chunk-bytes+)
            for count = (min +owned-chunk-bytes+ (- size start))
            do (unless (and (stringp chunk) (= (length chunk) (* 2 count)))
                 (fail-document "Incomplete or oversized record chunk" :path (vector :chunks index)))
               (loop for offset below count
                     for high = (position (char chunk (* 2 offset)) "0123456789ABCDEF")
                     for low = (position (char chunk (1+ (* 2 offset))) "0123456789ABCDEF")
                     do (unless (and high low)
                          (fail-document "Record chunks require uppercase hexadecimal bytes"
                                         :path (vector :chunks index)))
                        (setf (aref bytes (+ start offset)) (+ (* high 16) low))))
      (handler-case (libtmux.internal::strict-text bytes)
        (libtmux:decoding-error (condition)
          (fail-document "Record chunks are not complete UTF-8" :cause condition))))))

(defclass owned-record ()
  ((kind :initarg :kind) (data :initarg :data) (json :initarg :json))
  (:documentation "A private validated record; graph availability and authority are separate."))

(defun owned-declaration-value (value path context)
  (normalize-owned-declaration
   (if (and (eq :native (owned-context-mode context)) (typep value 'owned-declaration))
       (owned-declaration-data value) value) context path))
(defun encode-owned-declaration (value)
  (owned-wire-object value *owned-declaration-fields*))

(defun owned-physical-id (value model path context)
  (let ((text (owned-string value path context))
        (key (ecase model (:session :session/id) (:window :window/id) (:pane :pane/id))))
    (handler-case
        (progn
          (libtmux.internal::decode-scalar (libtmux.internal::registered-field key model) text)
          (unless (string= text (format nil "~C~D" (char text 0) (parse-integer text :start 1)))
            (fail-workspace "Physical IDs must use canonical decimal notation" :path path))
          text)
      (libtmux:decoding-error (condition)
        (fail-workspace "Invalid physical entity ID" :path path :cause condition)))))
(defun owned-session-id (value path context)
  (owned-physical-id value :session path context))
(defun owned-window-id (value path context)
  (owned-physical-id value :window path context))
(defun owned-pane-id (value path context)
  (owned-physical-id value :pane path context))
(defun owned-pid (value path context)
  (owned-integer value 1 2147483647 path context))
(defun owned-signed64 (value path context)
  (owned-integer value (- (ash 1 63)) (1- (ash 1 63)) path context))
(defun owned-unsigned64 (value path context)
  (owned-integer value 0 (1- (ash 1 64)) path context))

(defparameter *owned-daemon-fields*
  '((:pid "pid" owned-pid t) (:start "start" owned-signed64 t)
    (:process-start "process_start" owned-unsigned64 t)
    (:device "device" owned-unsigned64 t) (:inode "inode" owned-unsigned64 t)
    (:version "version" owned-nonempty-string t)))
(defparameter *owned-session-map-fields*
  '((:logical-id "logical_id" owned-logical-id t)
    (:physical-id "physical_id" owned-session-id t) (:name "name" owned-session-name t)))
(defparameter *owned-pane-map-fields*
  '((:logical-id "logical_id" owned-logical-id t) (:physical-id "physical_id" owned-pane-id t)))
(defparameter *owned-window-map-fields*
  '((:logical-id "logical_id" owned-logical-id t) (:physical-id "physical_id" owned-window-id t)
    (:session-id "session_id" owned-session-id t) (:index "index" owned-index t)
    (:name "name" owned-window-name t) (:layout "layout" owned-nonempty-string t)
    (:panes "panes" owned-pane-maps t encode-owned-pane-maps)))
(defparameter *owned-reference-fields*
  '((:revision "revision" owned-token t) (:bytes "bytes" owned-byte-count t)
    (:chunks "chunks" owned-chunk-count t)))

(defun owned-daemon-value (value path context)
  (normalize-owned-object value *owned-daemon-fields* path context))
(defun owned-session-map (value path context)
  (normalize-owned-object value *owned-session-map-fields* path context))
(defun owned-pane-map (value path context)
  (normalize-owned-object value *owned-pane-map-fields* path context))
(defun owned-window-map (value path context)
  (normalize-owned-object value *owned-window-map-fields* path context))
(defun owned-pane-maps (value path context)
  (owned-array value path context 1 1000 #'owned-pane-map))
(defun owned-window-maps (value path context)
  (owned-array value path context 1 100 #'owned-window-map))
(defun owned-reference (value path context)
  (let ((data (normalize-owned-object value *owned-reference-fields* path context)))
    (unless (= (getf data :chunks) (ceiling (getf data :bytes) +owned-chunk-bytes+))
      (fail-workspace "Record reference has an inconsistent chunk count" :path path))
    data))
(defun owned-previous (value path context)
  (if (or (and (eq :json (owned-context-mode context)) (eq value 'null))
          (and (eq :native (owned-context-mode context)) (null value)))
      (progn (owned-node context path) nil)
      (owned-reference value path context)))

(defun encode-owned-daemon (data) (owned-wire-object data *owned-daemon-fields*))
(defun encode-owned-session-map (data) (owned-wire-object data *owned-session-map-fields*))
(defun encode-owned-pane-maps (items)
  (map 'simple-vector (lambda (item) (owned-wire-object item *owned-pane-map-fields*)) items))
(defun encode-owned-window-maps (items)
  (map 'simple-vector (lambda (item) (owned-wire-object item *owned-window-map-fields*)) items))
(defun encode-owned-reference (data) (owned-wire-object data *owned-reference-fields*))
(defun encode-owned-previous (data)
  (if data (encode-owned-reference data) 'null))

(defparameter *owned-pending-fields*
  '((:schema "schema" owned-string t) (:workspace "workspace" owned-logical-id t)
    (:base "base" owned-head t) (:writer "writer" owned-token t)
    (:declaration "declaration" owned-declaration-value t encode-owned-declaration)))
(defparameter *owned-committed-fields*
  '((:schema "schema" owned-string t) (:workspace "workspace" owned-logical-id t)
    (:revision "revision" owned-token t) (:daemon "daemon" owned-daemon-value t encode-owned-daemon)
    (:declaration "declaration" owned-declaration-value t encode-owned-declaration)
    (:session "session" owned-session-map t encode-owned-session-map)
    (:windows "windows" owned-window-maps t encode-owned-window-maps)
    (:previous "previous" owned-previous t encode-owned-previous)
    (:pending "pending" owned-reference t encode-owned-reference)))

(defun owned-record-fields (kind)
  (case kind (:pending *owned-pending-fields*) (:committed *owned-committed-fields*)
        (otherwise (fail-workspace "Unknown owned record kind"))))

(defun validate-owned-mapping (data)
  (let* ((declaration (getf data :declaration))
         (session (getf data :session))
         (desired-session (getf declaration :session))
         (windows (getf data :windows))
         (desired-windows (getf desired-session :windows))
         (window-ids (make-hash-table :test #'equal))
         (pane-ids (make-hash-table :test #'equal))
         (indexes (make-hash-table :test #'eql)))
    (unless (and (string= (getf session :logical-id) (getf desired-session :id))
                 (string= (getf session :name) (getf desired-session :name))
                 (= (length windows) (length desired-windows)))
      (fail-workspace "Session mapping does not match its declaration" :path #(:session)))
    (loop for window across windows for wanted across desired-windows for index from 0
          for path = (vector :windows index)
          do (owned-unique (getf window :physical-id) window-ids path "physical window ID")
             (owned-unique (getf window :index) indexes path "mapped window index")
             (unless (and (string= (getf window :logical-id) (getf wanted :id))
                          (string= (getf window :session-id) (getf session :physical-id))
                          (string= (getf window :name) (getf wanted :name))
                          (or (not (nth-value 1 (plist-value wanted :index)))
                              (= (getf window :index) (getf wanted :index)))
                          (= (length (getf window :panes)) (length (getf wanted :panes))))
               (fail-workspace "Window mapping does not match its declaration and session" :path path))
             (loop for pane across (getf window :panes)
                   for desired across (getf wanted :panes) for pane-index from 0
                   for pane-path = (path+ path :panes pane-index)
                   do (owned-unique (getf pane :physical-id) pane-ids pane-path "physical pane ID")
                      (unless (string= (getf pane :logical-id) (getf desired :id))
                        (fail-workspace "Pane mapping does not match its declaration" :path pane-path))))))

(defun normalize-owned-record (kind value context)
  (let* ((fields (owned-record-fields kind))
         (schema (if (eq kind :pending) "libtmux.lisp.workspace.pending/1"
                     "libtmux.lisp.workspace.owned/1"))
         (data (normalize-owned-object value fields #() context schema)))
    (unless (string= (getf data :workspace) (getf (getf data :declaration) :id))
      (fail-workspace "Record workspace ID differs from its declaration" :path #(:workspace)))
    (if (eq kind :pending)
        (when (string= (getf data :base) (getf data :writer))
          (fail-workspace "Pending writer token equals its base head" :path #(:writer)))
        (progn
          (validate-owned-mapping data)
          (unless (string= (getf data :revision) (getf (getf data :pending) :revision))
            (fail-workspace "Pending reference differs from the committed revision" :path #(:pending)))
          (when (and (getf data :previous)
                     (string= (getf data :revision) (getf (getf data :previous) :revision)))
            (fail-workspace "A committed record cannot reference itself as previous" :path #(:previous)))))
    data))

(defun make-owned-record (kind value)
  "Validate inert native record data; this does not prove a live graph or ownership."
  (let ((data (normalize-owned-record kind value (make-owned-context :native))))
    (make-instance 'owned-record :kind kind :data data
                   :json (owned-json (owned-wire-object data (owned-record-fields kind))))))
(defun owned-record-data (record) (deep-copy (slot-value record 'data)))
(defun owned-record-json (record) (copy-seq (slot-value record 'json)))

(defun parse-owned-record (kind source)
  (handler-case
      (let ((data (normalize-owned-record kind (parse-owned-tree source) (make-owned-context :json))))
        (make-instance 'owned-record :kind kind :data data
                       :json (owned-json (owned-wire-object data (owned-record-fields kind)))))
    (invalid-workspace-document (condition) (error condition))
    (invalid-workspace (condition) (fail-document "Owned record violates its schema" :cause condition))))

(defun encode-owned-record (record)
  (let* ((kind (slot-value record 'kind)) (data (slot-value record 'data))
         (revision (getf data (if (eq kind :pending) :writer :revision))))
    (encode-owned-envelope kind revision (slot-value record 'json))))

(defun decode-owned-record (workspace kind revision descriptor chunks)
  (let* ((workspace (owned-logical-id workspace #(:workspace) (make-owned-context :native)))
         (record (parse-owned-record kind (decode-owned-envelope kind revision descriptor chunks)))
         (data (slot-value record 'data))
         (actual (getf data (if (eq kind :pending) :writer :revision))))
    (unless (and (string= workspace (getf data :workspace)) (string= revision actual))
      (fail-document "Record does not match the selected workspace and revision"))
    record))
