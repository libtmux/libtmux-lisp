(in-package #:libtmux.tests)

(in-suite json)

(defun write-json-filter (filter &rest arguments)
  (apply #'uiop:symbol-call :libtmux.json :write-filter filter arguments))

(defun read-json-filter (source &rest arguments)
  (apply #'uiop:symbol-call :libtmux.json :read-filter source arguments))

(defun json-document-path (condition)
  (uiop:symbol-call :libtmux.json :document-path condition))

(defun json-document-limit (condition)
  (uiop:symbol-call :libtmux.json :document-limit condition))

(defun invalid-document-p (condition)
  (let ((class (find-symbol "INVALID-FILTER-DOCUMENT" :libtmux.json)))
    (and class (typep condition class))))

(defun limit-document-p (condition)
  (let ((class (find-symbol "FILTER-DOCUMENT-LIMIT-EXCEEDED" :libtmux.json)))
    (and class (typep condition class))))

(defmacro signals-invalid-document (&body body)
  `(handler-case
       (progn ,@body (fail "Invalid filter document was accepted"))
     (condition (condition)
       (is (invalid-document-p condition)))))

(test json-package-is-separately-loadable
  (is (find-package :libtmux.json)))

(test json-round-trip-preserves-false-empty-and-local-semantics
  (let* ((filter
           (libtmux.query:compile-filter
            :pane '(:and (:= :pane/active nil)
                         (:in :pane/current-command #()))))
         (document (write-json-filter filter))
         (restored (read-json-filter document))
         (panes (libtmux:panes (synthetic-snapshot))))
    (is (search "\"schema\":\"libtmux.lisp.filter/1\"" document))
    (is (search "[\"=\",\"pane/active\",false]" document))
    (is (search "[\"in\",\"pane/current-command\",[]]" document))
    (is (null (search "null" document)))
    (is (equalp '(nil nil)
                (loop for pane across panes
                      collect (not (null
                                    (funcall (libtmux.query:predicate restored)
                                             pane))))))))

(test json-envelope-is-closed-complete-and-duplicate-free
  (signals-invalid-document
    (read-json-filter
     "{\"schema\":\"libtmux.lisp.filter/1\",\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"and\"]}"))
  (signals-invalid-document
    (read-json-filter
     "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"and\"],\"extra\":true}"))
  (signals-invalid-document
    (read-json-filter
     "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1}"))
  (signals-invalid-document
    (read-json-filter
     "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":null}"))
  (signals-invalid-document
    (read-json-filter
     "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"=\",\"pane/active\",null]}")))

(test json-external-names-are-allowlisted-without-interning
  (let ((name "LIBTMUX-UNTRUSTED-EXTERNAL-OPERATOR-7E41"))
    (is (null (find-symbol name :keyword)))
    (signals-invalid-document
      (read-json-filter
       (format nil
               "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"~A\"]}"
               name)))
    (is (null (find-symbol name :keyword)))))

(test json-document-path-owns-member-names
  (handler-case
      (progn
        (read-json-filter
         "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"and\"],\"unexpected\":true}")
        (fail "Unknown filter-document member was accepted"))
    (condition (condition)
      (if (invalid-document-p condition)
          (let ((path (json-document-path condition)))
            (is (string= "unexpected" (aref path 0)))
            (setf (char (aref path 0) 0) #\X)
            (is (string= "unexpected"
                         (aref (json-document-path condition) 0))))
          (error condition)))))

(test json-decoder-enforces-whole-input-and-structural-bounds
  (let ((valid
          "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"and\"]}"))
    (signals-invalid-document (read-json-filter valid :max-input-bytes 20))
    (signals-invalid-document (read-json-filter valid :max-depth 1))
    (signals-invalid-document (read-json-filter valid :max-nodes 3))
    (signals-invalid-document (read-json-filter valid :max-string-length 8)))
  (signals-invalid-document
    (read-json-filter
     "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"in\",\"pane/width\",[1,2]]}"
     :max-membership 1))
  (let ((digits (make-string 129 :initial-element #\1)))
    (signals-invalid-document
      (read-json-filter
       (format nil
               "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"=\",\"pane/width\",~A]}"
               digits))))
  (signals-invalid-document
    (libtmux.json::validate-numeric-token-bounds "1e1000000000" 128))
  (signals-invalid-document
    (read-json-filter
     "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"in\",\"pane/current-command\",\"\"]}"))
  (handler-case
      (progn
        (read-json-filter
         "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"and\"]}"
         :max-string-length 8)
        (fail "String limit was not enforced"))
    (condition (condition)
      (is (limit-document-p condition))
      (is (eq :max-string-length (json-document-limit condition)))))
  (let ((document
          (format nil
                  "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"and\"~{,~A~}]}"
                  (make-list 10 :initial-element "[\"and\"]"))))
    (is (typep (read-json-filter document :max-nodes 26)
               'libtmux.query:compiled-filter))))

(test json-integer-negative-zero-normalizes-to-zero
  (let* ((filter
           (read-json-filter
            "{\"schema\":\"libtmux.lisp.filter/1\",\"model\":\"pane\",\"registryVersion\":1,\"expression\":[\"=\",\"pane/index\",-0]}"))
         (expression (libtmux.query:expression filter)))
    (is (eql 0 (third expression)))
    (is (integerp (third expression)))))

(test json-regex-round-trip-requires-explicit-read-opt-in
  (let* ((filter
           (libtmux.query:compile-filter
            :pane '(:regex-search :pane/current-command
                    (:cl-ppcre "^NV" :case-insensitive-mode t))))
         (document (write-json-filter filter)))
    (is (search "\"engine\":\"cl-ppcre\"" document))
    (signals-invalid-document (read-json-filter document))
    (let ((restored (read-json-filter document :allow-regex t)))
      (is (funcall (libtmux.query:predicate restored)
                   (aref (libtmux:panes (synthetic-snapshot)) 0))))))

(test json-relation-round-trip-preserves-target-models
  (let* ((filter
           (libtmux.query:compile-filter
            :session
            '(:any :session/window-links
              (:is :link/window
               (:any :window/panes
                (:= :pane/current-command "nvim"))))))
         (restored (read-json-filter (write-json-filter filter)))
         (sessions (libtmux:sessions (synthetic-snapshot))))
    (is (funcall (libtmux.query:predicate restored) (aref sessions 0)))))

(test json-output-supports-explicit-streams
  (let ((filter (libtmux.query:compile-filter :pane '(:and))))
    (with-output-to-string (stream)
      (is (null (write-json-filter filter :stream stream))))
    (is (typep (read-json-filter (write-json-filter filter :pretty t))
               'libtmux.query:compiled-filter))))

(test json-writer-rejects-destinations-it-does-not-own
  (let ((filter (libtmux.query:compile-filter :pane '(:and)))
        (pathname
          (make-pathname
           :directory '(:relative "libtmux-json-pathname-destinations-are-rejected")
           :name "filter" :type "json")))
    (signals type-error (write-json-filter filter :stream pathname))
    (let ((stream (flexi-streams:make-in-memory-output-stream)))
      (unwind-protect
           (progn
             (signals type-error (write-json-filter filter :stream stream))
             (is (open-stream-p stream)))
        (when (open-stream-p stream) (close stream))))))

(test json-writer-accepts-the-compiled-filter-depth
  (let ((form '(:and)))
    (dotimes (index 63)
      (declare (ignore index))
      (setf form (list :not form)))
    (let ((filter (libtmux.query:compile-filter :pane form :max-depth 128)))
      (is (stringp (write-json-filter filter))))))
