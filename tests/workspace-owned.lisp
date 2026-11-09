(in-package #:libtmux.tests)

(in-suite workspace)

(test owned-state-inventory-is-complete-and-namespace-exact
  (let* ((key "@libtmux.workspace.61.control")
         (text (format nil "exit-empty off~%user-keys~%~A \"idle\"~%@libtmux.workspace.612E6368696C64.control \"other\"~%" key))
         (keys (workspace-call :parse-owned-inventory "a" text)))
    (is (equalp #("@libtmux.workspace.61.control") keys))
    (setf (char (aref keys 0) 0) #\X)
    (is (equalp #("@libtmux.workspace.61.control")
                (workspace-call :parse-owned-inventory "a" text)))
    (dolist (bad (list "" (string #\Newline) (format nil " ~C~%" #\Tab)
                      (format nil "~A \"incomplete\"" key)
                      (format nil "~A \"one\"~%~A \"two\"~%" key key)
                      (format nil "@libtmux.workspace.61.unknown \"value\"~%")
                      (format nil "@libtmux.workspace.61.pending.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.chunk.00 \"AA\"~%")))
      (signals libtmux.workspace:invalid-workspace
        (workspace-call :parse-owned-inventory "a" bad)))))

(defun owned-description ()
  (list :schema "libtmux.lisp.workspace/2" :id (copy-seq "a.child")
        :session
        (list :id "main" :name "owned"
              :environment (vector (cons (copy-seq "Z") (copy-seq "last"))
                                   (cons (copy-seq "A") (copy-seq "")))
              :windows
              (vector (list :id "editor" :name "same" :index 1
                            :layout (list :custom (copy-seq "layout text"))
                            :panes (vector (list :id "first" :command #("/bin/cat"))))
                      (list :id "logs" :name "same"
                            :panes (vector (list :id "second" :shell-command "exec cat")))))))

(test owned-declaration-normalization-canonicalization-and-ownership
  (let* ((source (owned-description))
         (declaration (workspace-call :make-owned-declaration source))
         (data (workspace-call :owned-declaration-data declaration))
         (json (workspace-call :owned-declaration-json declaration)))
    (is (equalp #(("A" . "") ("Z" . "last"))
                (getf (getf data :session) :environment)))
    (is (string= json (workspace-call :owned-declaration-json
                                    (workspace-call :parse-owned-declaration json))))
    (setf (char (getf source :id) 0) #\X
          (char (cdr (aref (getf (getf source :session) :environment) 0)) 0) #\X
          (char (second (getf (aref (getf (getf source :session) :windows) 0) :layout)) 0) #\X
          (char (getf data :id) 0) #\X
          (char json 0) #\X)
    (is (string= "a.child" (getf (workspace-call :owned-declaration-data declaration) :id)))
    (is (not (char= #\X (char (workspace-call :owned-declaration-json declaration) 0))))))

(test owned-declaration-rejects-invalid-and-duplicate-logical-ids
  (dolist (id (list "" "_bad" "not/allowed" "λ" (make-string 65 :initial-element #\a)))
    (let ((data (owned-description)))
      (setf (getf data :id) id)
      (signals-workspace :invalid-workspace (workspace-call :make-owned-declaration data))))
  (let* ((data (owned-description))
         (windows (getf (getf data :session) :windows)))
    (setf (getf (aref (getf (aref windows 1) :panes) 0) :id) "first")
    (signals-workspace :invalid-workspace (workspace-call :make-owned-declaration data)))
  (signals-workspace :invalid-workspace
    (workspace-call :make-workspace (owned-description)))
  (let* ((data (owned-description)) (windows (getf (getf data :session) :windows)))
    (setf (getf (aref windows 0) :id) "first")
    (is (stringp (workspace-call :owned-declaration-json
                                (workspace-call :make-owned-declaration data))))
    (setf (getf (aref windows 1) :id) "first")
    (signals-workspace :invalid-workspace (workspace-call :make-owned-declaration data))))

(test owned-control-and-key-grammar
  (let* ((revision (make-string 32 :initial-element #\A))
         (writer (make-string 32 :initial-element #\B))
         (idle (workspace-call :make-owned-control :idle revision))
         (busy (workspace-call :make-owned-control :busy revision writer)))
    (is (eq :idle (getf (workspace-call :parse-owned-control idle) :state)))
    (is (string= writer (getf (workspace-call :parse-owned-control busy) :writer)))
    (is (string= "@libtmux.workspace.61."
                 (workspace-call :owned-namespace "a")))
    (is (string= "@libtmux.workspace.612E6368696C64."
                 (workspace-call :owned-namespace "a.child")))
    (dolist (value (list "W2I.0" (concatenate 'string idle ".extra")
                         (concatenate 'string "W2B." revision "." revision)))
      (signals-workspace :invalid-workspace (workspace-call :parse-owned-control value)))))

(test owned-chunks-preserve-split-unicode-and-refuse-incomplete-frames
  (let ((revision (make-string 32 :initial-element #\A))
        (text (format nil "~Aλ~%" (make-string 2047 :initial-element #\a))))
    (multiple-value-bind (descriptor chunks)
        (workspace-call :encode-owned-envelope :pending revision text)
      (is (= 2 (length chunks)))
      (is (string= text (workspace-call :decode-owned-envelope :pending revision descriptor chunks)))
      (signals-workspace :invalid-workspace
        (workspace-call :decode-owned-envelope :committed revision descriptor chunks))
      (signals-workspace :invalid-workspace
        (workspace-call :decode-owned-envelope :pending revision descriptor (subseq chunks 0 1)))
      (setf (char (aref chunks 0) (- (length (aref chunks 0)) 2)) #\c)
      (signals-workspace :invalid-workspace
        (workspace-call :decode-owned-envelope :pending revision descriptor chunks)))
    (multiple-value-bind (descriptor chunks)
        (workspace-call :encode-owned-envelope :pending revision "a")
      (setf (aref chunks 0) "FF")
      (signals-workspace :invalid-workspace
        (workspace-call :decode-owned-envelope :pending revision descriptor chunks)))))

(defun owned-pending-data ()
  (list :schema "libtmux.lisp.workspace.pending/1" :workspace "a.child"
        :base "0" :writer (make-string 32 :initial-element #\A)
        :declaration (owned-description)))

(defun owned-committed-data ()
  (let ((revision (make-string 32 :initial-element #\A)))
    (list :schema "libtmux.lisp.workspace.owned/1" :workspace "a.child"
          :revision revision
          :daemon (list :pid 7 :start 10 :process-start 20 :device 1 :inode 2 :version "3.8")
          :declaration (owned-description)
          :session (list :logical-id "main" :physical-id "$8" :name "owned")
          :windows
          (workspace-call :deep-copy
          #((:logical-id "editor" :physical-id "@10" :session-id "$8" :index 1
             :name "same" :layout "realized-1"
             :panes #((:logical-id "first" :physical-id "%20")))
            (:logical-id "logs" :physical-id "@11" :session-id "$8" :index 4
             :name "same" :layout "realized-2"
             :panes #((:logical-id "second" :physical-id "%21")))))
          :previous nil :pending (list :revision revision :bytes 2 :chunks 1))))

(test owned-record-canonical-roundtrip-and-selected-frame
  (dolist (case (list (list :pending (owned-pending-data))
                     (list :committed (owned-committed-data))))
    (destructuring-bind (kind data) case
      (let* ((record (workspace-call :make-owned-record kind data))
             (json (workspace-call :owned-record-json record))
             (revision (if (eq kind :pending) (getf data :writer) (getf data :revision))))
        (is (string= json (workspace-call :owned-record-json
                                        (workspace-call :parse-owned-record kind json))))
        (multiple-value-bind (descriptor chunks) (workspace-call :encode-owned-record record)
          (is (string= json (workspace-call :owned-record-json
                                          (workspace-call :decode-owned-record
                                                          "a.child" kind revision descriptor chunks))))
          (signals-workspace :invalid-workspace
            (workspace-call :decode-owned-record "other" kind revision descriptor chunks)))
        (setf (char (getf (getf data :declaration) :id) 0) #\X
              (char json 0) #\X)
        (let ((projection (workspace-call :owned-record-data record)))
          (setf (getf projection :workspace) "changed")
          (is (string= "a.child" (getf (workspace-call :owned-record-data record) :workspace))))))))

(test owned-record-rejects-false-null-confusion-and-incoherent-mappings
  (let* ((record (workspace-call :make-owned-record :committed (owned-committed-data)))
         (json (workspace-call :owned-record-json record))
         (needle "\"previous\":null")
         (position (search needle json)))
    (is (not (null position)))
    (dolist (replacement '("false" "[]" "{}"))
      (signals-workspace :invalid-workspace
        (workspace-call :parse-owned-record :committed
                        (concatenate 'string (subseq json 0 position)
                                     "\"previous\":" replacement
                                     (subseq json (+ position (length needle))))))))
  (let* ((data (owned-committed-data))
         (windows (copy-tree (coerce (getf data :windows) 'list))))
    (setf (getf (getf data :session) :physical-id) "$9")
    (signals-workspace :invalid-workspace
      (workspace-call :make-owned-record :committed data))
    (setf data (owned-committed-data))
    (setf (getf (aref (getf (second windows) :panes) 0) :physical-id) "%20"
          (getf data :windows) (coerce windows 'vector))
    (signals-workspace :invalid-workspace
      (workspace-call :make-owned-record :committed data))))

(test owned-codec-enforces-native-node-byte-and-selected-revision-bounds
  (let* ((data (owned-description))
         (window (aref (getf (getf data :session) :windows) 0))
         (argv (make-array 256 :initial-element "")))
    (setf (aref argv 0) "/bin/cat"
          (getf (getf data :session) :windows) (vector window)
          (getf window :panes)
          (map 'vector (lambda (index) (list :id (format nil "p~D" index) :command argv))
               (loop for index below 256 collect index)))
    (handler-case (progn (workspace-call :make-owned-declaration data)
                         (fail "Native record node limit was not enforced"))
      (condition (condition)
        (unless (workspace-condition-p condition :invalid-workspace) (error condition))
        (is (eq :max-nodes (workspace-call :workspace-limit condition))))))
  (signals-workspace :invalid-workspace
    (workspace-call :encode-owned-envelope :pending (make-string 32 :initial-element #\A)
                    (make-string 1048577 :initial-element #\a)))
  (let* ((record (workspace-call :make-owned-record :committed (owned-committed-data)))
         (revision (make-string 32 :initial-element #\B)))
    (multiple-value-bind (descriptor chunks)
        (workspace-call :encode-owned-envelope :committed revision
                        (workspace-call :owned-record-json record))
      (signals-workspace :invalid-workspace
        (workspace-call :decode-owned-record "a.child" :committed revision descriptor chunks)))))

(test owned-record-json-integer-zero-does-not-admit-fractional-or-native-floats
  (let ((data (owned-committed-data)))
    (setf (getf (getf data :daemon) :start) 0)
    (let* ((record (workspace-call :make-owned-record :committed data))
           (json (workspace-call :owned-record-json record))
           (position (search "\"start\":0" json))
           (prefix (subseq json 0 position))
           (suffix (subseq json (+ position (length "\"start\":0")))))
      (is (string= json
                   (workspace-call :owned-record-json
                                   (workspace-call :parse-owned-record :committed
                                                   (concatenate 'string prefix "\"start\":-0" suffix)))))
      (signals-workspace :invalid-workspace
        (workspace-call :parse-owned-record :committed
                        (concatenate 'string prefix "\"start\":0.0" suffix))))
    (setf (getf (getf data :daemon) :start) 0.0d0)
    (signals-workspace :invalid-workspace (workspace-call :make-owned-record :committed data))))
