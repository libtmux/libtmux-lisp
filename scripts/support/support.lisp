;;; Shared helpers for the support scripts: failures, child processes with
;;; deadlines, text and JSON files, checksums and temporary directories.
;;;
;;; Every script loads tools/load.lisp first, then this file. Scripts live in
;;; scripts/<name>/, so a script finds the project root with
;;; (directory-above *load-truename* 2).

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defpackage #:libtmux.scripts
  (:use #:cl)
  (:export #:*library-load* #:script-failure #:fail #:main-when-script
           #:directory-above #:monotonic-seconds
           #:run #:process-exited-p #:descriptor-readable-p #:pidfd-open
           #:read-text #:write-text #:sha256-file #:git #:find-program
           #:with-temporary-directory #:environment-with #:merge-environment
           #:obj #:jref #:jhas #:jset #:json-equal #:json-parse #:json-string
           #:json-write-file #:json-read-file))

(in-package #:libtmux.scripts)

(defvar *library-load* nil
  "True while a script file is loaded for its functions, not to run it.")

(define-condition script-failure (error)
  ((message :initarg :message :reader script-failure-message))
  (:report (lambda (condition stream)
             (write-string (script-failure-message condition) stream))))

(defun fail (control &rest arguments)
  "Signal SCRIPT-FAILURE with a formatted message."
  (error 'script-failure :message (apply #'format nil control arguments)))

(defun main-when-script (function)
  "Call FUNCTION when this file is the script SBCL runs, then exit with its status.
FUNCTION returns an exit code, or NIL for success. A SCRIPT-FAILURE prints its
message and exits 1. Loading a compiled file or binding *LIBRARY-LOAD* skips it."
  (when (and *load-truename* (not *library-load*)
             (equal "lisp" (pathname-type *load-truename*)))
    (let ((code (handler-case (or (funcall function) 0)
                  (script-failure (condition)
                    (format *error-output* "~&~A: ~A~%"
                            (pathname-name *load-truename*) condition)
                    1))))
      (finish-output *standard-output*)
      (finish-output *error-output*)
      (uiop:quit code))))

(defun directory-above (pathname &optional (levels 1))
  "Return the directory LEVELS above the directory that holds PATHNAME."
  (truename (merge-pathnames
             (format nil "~{~A~}" (loop repeat levels collect "../"))
             (make-pathname :name nil :type nil :defaults pathname))))

(defun monotonic-seconds ()
  (/ (get-internal-real-time) internal-time-units-per-second))

;;; Descriptors

(sb-alien:define-alien-routine ("pidfd_open" pidfd-open) sb-alien:int
  (pid sb-alien:int) (flags sb-alien:unsigned-int))

(sb-alien:define-alien-type nil
  (sb-alien:struct poll-entry
    (descriptor sb-alien:int) (events sb-alien:short) (returned sb-alien:short)))

(sb-alien:define-alien-routine ("poll" %poll) sb-alien:int
  (entries (* (sb-alien:struct poll-entry))) (count sb-alien:unsigned-long)
  (milliseconds sb-alien:int))

(defun descriptor-readable-p (descriptor seconds)
  "Wait up to SECONDS (NIL: forever) for DESCRIPTOR to become readable.
Return true when it is, such as a pidfd whose process exited."
  (let ((deadline (and seconds (+ (monotonic-seconds) seconds))))
    (sb-alien:with-alien ((entry (sb-alien:struct poll-entry)))
      (setf (sb-alien:slot entry 'descriptor) descriptor
            (sb-alien:slot entry 'events) 1
            (sb-alien:slot entry 'returned) 0)
      (loop
        (let* ((remaining (and deadline (max 0 (- deadline (monotonic-seconds)))))
               (count (%poll (sb-alien:addr entry) 1
                             (if remaining (ceiling (* 1000 remaining)) -1))))
          (cond ((plusp count) (return t))
                ((zerop count) (return nil))
                ((/= (sb-alien:get-errno) sb-unix:eintr)
                 (fail "poll failed with errno ~D" (sb-alien:get-errno)))))))))

(defun process-exited-p (process seconds)
  "Wait up to SECONDS for run-program PROCESS to exit; return true when it did."
  (let ((descriptor (pidfd-open (sb-ext:process-pid process) 0)))
    (if (minusp descriptor)
        (progn (sb-ext:process-wait process) t)
        (unwind-protect (descriptor-readable-p descriptor seconds)
          (sb-posix:close descriptor)))))

;;; Files

(defun read-text (path)
  (uiop:read-file-string path :external-format '(:utf-8 :replacement #\?)))

(defun write-text (path text)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :external-format :utf-8)
    (write-string text stream))
  path)

(defmacro with-temporary-directory ((name &optional (prefix "libtmux-script")) &body body)
  "Bind NAME to a fresh directory pathname and delete it after BODY."
  `(let ((,name (uiop:ensure-directory-pathname
                 (sb-posix:mkdtemp
                  (uiop:native-namestring
                   (merge-pathnames ,(concatenate 'string prefix "-XXXXXX")
                                    (uiop:temporary-directory)))))))
     (unwind-protect (progn ,@body)
       (uiop:delete-directory-tree ,name :validate t :if-does-not-exist :ignore))))

(defun temporary-file ()
  (multiple-value-bind (descriptor path)
      (sb-posix:mkstemp (uiop:native-namestring
                         (merge-pathnames "libtmux-script-XXXXXX"
                                          (uiop:temporary-directory))))
    (sb-posix:close descriptor)
    path))

;;; Child processes

(defun environment-with (base &rest names-and-values)
  "Return the environment list BASE with the given NAME VALUE pairs set.
A NIL value removes the name."
  (let* ((names (loop for (name nil) on names-and-values by #'cddr collect name))
         (kept (remove-if (lambda (entry)
                            (some (lambda (name)
                                    (uiop:string-prefix-p (concatenate 'string name "=") entry))
                                  names))
                          base)))
    (append kept (loop for (name value) on names-and-values by #'cddr
                       when value collect (concatenate 'string name "=" value)))))

(defun merge-environment (&rest names-and-values)
  "Return this process's environment with the given NAME VALUE pairs set."
  (apply #'environment-with (sb-ext:posix-environ) names-and-values))

(defun destination (value)
  "Translate a RUN output designator for SB-EXT:RUN-PROGRAM; second value is a temp path."
  (case value
    (:string (let ((path (temporary-file))) (values path path)))
    (:inherit t)
    ((nil) nil)
    (t value)))

(defun run (argv &key directory environment input (output :string) (error-output :string)
                   timeout (check t))
  "Run ARGV, searching PATH, and return (values EXIT-CODE STDOUT STDERR).
INPUT is a string for stdin, :INHERIT or NIL (no input). OUTPUT and ERROR-OUTPUT
are :STRING (captured and returned), :INHERIT, NIL (discarded), a pathname
(written), and for ERROR-OUTPUT also :OUTPUT (merged into stdout). TIMEOUT
kills the child's process group after that many seconds. CHECK signals
SCRIPT-FAILURE for a timeout or nonzero exit."
  (let ((input-file (and (stringp input) (write-text (temporary-file) input)))
        (captured nil))
    (multiple-value-bind (output-target output-temp) (destination output)
      (multiple-value-bind (error-target error-temp)
          (if (eq error-output :output) (values :output nil) (destination error-output))
        (unwind-protect
             (let* ((process (sb-ext:run-program
                              (first argv) (rest argv) :search t :wait nil
                              :input (cond (input-file input-file) ((eq input :inherit) t))
                              :output output-target :if-output-exists :supersede
                              :error error-target :if-error-exists :supersede
                              :environment (or environment (sb-ext:posix-environ))
                              :directory (and directory (uiop:native-namestring directory))))
                    (pid (sb-ext:process-pid process))
                    (timed-out nil))
               (if (null timeout)
                   (sb-ext:process-wait process)
                   (unless (process-exited-p process timeout)
                     (setf timed-out t)
                     (ignore-errors
                      (sb-posix:kill (if (eql pid (sb-posix:getpgid pid)) (- pid) pid) 9))
                     (sb-ext:process-wait process)))
               (let ((code (sb-ext:process-exit-code process))
                     (out (and output-temp (read-text output-temp)))
                     (err (and error-temp (read-text error-temp))))
                 (setf captured t)
                 (when (and check (or timed-out (not (eql 0 code))))
                   (fail "~{~A~^ ~} ~A~@[:~%~A~]" argv
                         (if timed-out
                             (format nil "timed out after ~A seconds" timeout)
                             (format nil "exited ~D" code))
                         (and err (plusp (length err)) (string-trim '(#\Newline) err))))
                 (values code out err)))
          (dolist (path (list input-file output-temp error-temp))
            (when (and path (probe-file path)) (delete-file path)))
          captured)))))

(defun sha256-file (path)
  "Return the lowercase hexadecimal SHA-256 digest of the file at PATH."
  (subseq (nth-value 1 (run (list "sha256sum" "--" (uiop:native-namestring path)))) 0 64))

(defun git (directory &rest arguments)
  "Run git in DIRECTORY and return its standard output without the final newline."
  (string-right-trim '(#\Newline)
                     (nth-value 1 (run (cons "git" arguments) :directory directory))))

;;; Programs

(defun find-program (name)
  "Return the truename of the executable NAME, searched on PATH unless it has a slash."
  (let ((candidates (if (find #\/ name)
                        (list name)
                        (mapcar (lambda (directory) (concatenate 'string directory "/" name))
                                (uiop:split-string (or (uiop:getenv "PATH") "") :separator '(#\:))))))
    (loop for candidate in candidates
          when (and (probe-file candidate)
                    (zerop (sb-posix:access candidate sb-posix:x-ok)))
            return (truename candidate))))

;;; JSON
;;;
;;; An object is (:OBJECT (KEY . VALUE)...), an array a vector. true, false and
;;; null are :TRUE, :FALSE and :NULL. Objects keep their order, and JSON-STRING
;;; matches the layout of Python's json.dumps(indent=2, ensure_ascii=False), so
;;; generated files stay byte-identical across the port.

(defun obj (&rest keys-and-values)
  (cons :object (loop for (key value) on keys-and-values by #'cddr
                      collect (cons key value))))

(defun jhas (value key)
  (and (consp value) (eq :object (car value))
       (assoc key (cdr value) :test #'string=)))

(defun jref (value &rest keys)
  "Index VALUE by object keys and array positions; signal when one is absent."
  (dolist (key keys value)
    (setf value
          (cond ((and (integerp key) (vectorp value) (< -1 key (length value)))
                 (aref value key))
                ((and (stringp key) (jhas value key)) (cdr (jhas value key)))
                (t (fail "JSON value has no ~S" key))))))

(defun jset (object key value)
  "Set KEY in the JSON OBJECT, appending it when absent; return OBJECT."
  (let ((cell (jhas object key)))
    (if cell
        (setf (cdr cell) value)
        (setf (cdr object) (append (cdr object) (list (cons key value)))))
    object))

(defun json-equal (a b)
  "Deep equality of JSON values; objects compare without regard to member order."
  (cond ((and (stringp a) (stringp b)) (string= a b))
        ((and (numberp a) (numberp b)) (= a b))
        ((and (vectorp a) (vectorp b) (not (stringp a)) (not (stringp b)))
         (and (= (length a) (length b)) (every #'json-equal a b)))
        ((and (consp a) (consp b) (eq :object (car a)) (eq :object (car b)))
         (and (= (length (cdr a)) (length (cdr b)))
              (every (lambda (pair)
                       (let ((other (jhas b (car pair))))
                         (and other (json-equal (cdr pair) (cdr other)))))
                     (cdr a))))
        (t (eq a b))))

(defun json-parse (text)
  (let ((position 0) (length (length text)))
    (labels ((peek () (and (< position length) (char text position)))
             (skip ()
               (loop while (member (peek) '(#\Space #\Tab #\Newline #\Return))
                     do (incf position)))
             (expect (character)
               (skip)
               (unless (eql character (peek))
                 (fail "Invalid JSON at offset ~D: expected ~S" position character))
               (incf position))
             (literal (word value)
               (unless (and (<= (+ position (length word)) length)
                            (string= word text :start2 position :end2 (+ position (length word))))
                 (fail "Invalid JSON literal at offset ~D" position))
               (incf position (length word))
               value)
             (hex4 ()
               (prog1 (parse-integer text :start position :end (+ position 4) :radix 16)
                 (incf position 4)))
             (parse-string ()
               (expect #\")
               (with-output-to-string (out)
                 (loop
                   (let ((character (peek)))
                     (unless character (fail "Unterminated JSON string"))
                     (incf position)
                     (cond ((char= character #\") (return))
                           ((char/= character #\\) (write-char character out))
                           (t (let ((escape (peek)))
                                (incf position)
                                (case escape
                                  (#\n (write-char #\Newline out))
                                  (#\t (write-char #\Tab out))
                                  (#\r (write-char #\Return out))
                                  (#\b (write-char #\Backspace out))
                                  (#\f (write-char #\Page out))
                                  (#\u (let ((code (hex4)))
                                         (when (and (<= #xD800 code #xDBFF)
                                                    (eql #\\ (peek)))
                                           (incf position 2)
                                           (setf code (+ #x10000 (ash (- code #xD800) 10)
                                                         (- (hex4) #xDC00))))
                                         (write-char (code-char code) out)))
                                  ((#\" #\\ #\/) (write-char escape out))
                                  (t (fail "Invalid JSON escape at offset ~D" position))))))))))
             (parse-number ()
               (let ((start position))
                 (loop while (find (peek) "+-0123456789.eE") do (incf position))
                 (let ((token (subseq text start position)))
                   (if (every (lambda (c) (or (digit-char-p c) (char= c #\-))) token)
                       (parse-integer token)
                       (let ((*read-default-float-format* 'double-float) (*read-eval* nil))
                         (let ((value (read-from-string token)))
                           (unless (realp value) (fail "Invalid JSON number ~S" token))
                           (float value 1d0)))))))
             (parse-value ()
               (skip)
               (case (peek)
                 (#\{ (incf position)
                  (skip)
                  (if (eql #\} (peek))
                      (progn (incf position) (list :object))
                      (cons :object
                            (loop collect (let ((key (parse-string)))
                                            (expect #\:)
                                            (cons key (parse-value)))
                                  do (skip)
                                  while (eql #\, (peek))
                                  do (incf position)
                                  finally (expect #\})))))
                 (#\[ (incf position)
                  (skip)
                  (if (eql #\] (peek))
                      (progn (incf position) (vector))
                      (coerce (loop collect (parse-value)
                                    do (skip)
                                    while (eql #\, (peek))
                                    do (incf position)
                                    finally (expect #\]))
                              'simple-vector)))
                 (#\" (parse-string))
                 (#\t (literal "true" :true))
                 (#\f (literal "false" :false))
                 (#\n (literal "null" :null))
                 (t (parse-number)))))
      (prog1 (parse-value)
        (skip)
        (when (< position length)
          (fail "Trailing text after JSON value at offset ~D" position))))))

(defun json-read-file (path)
  (json-parse (read-text path)))

(defun write-json-string (string stream)
  (write-char #\" stream)
  (loop for character across string
        for code = (char-code character)
        do (case character
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (#\Backspace (write-string "\\b" stream))
             (#\Page (write-string "\\f" stream))
             (t (if (< code 32)
                    (format stream "\\u~(~4,'0x~)" code)
                    (write-char character stream)))))
  (write-char #\" stream))

(defun write-json-number (number stream)
  (cond ((integerp number) (format stream "~D" number))
        ((or (sb-ext:float-infinity-p number) (sb-ext:float-nan-p number))
         (fail "JSON cannot hold ~A" number))
        (t (let ((*read-default-float-format* 'double-float))
             (format stream "~A" (float number 1d0))))))

(defun write-json (value stream indent sort-keys level)
  (labels ((newline (depth)
             (when indent
               (write-char #\Newline stream)
               (dotimes (i (* indent depth)) (write-char #\Space stream))))
           (items (open close list function)
             (write-char open stream)
             (when list
               (loop for item in list for first = t then nil
                     do (unless first (write-string (if indent "," ", ") stream))
                        (newline (1+ level))
                        (funcall function item))
               (newline level))
             (write-char close stream)))
    (cond ((eq value :true) (write-string "true" stream))
          ((eq value :false) (write-string "false" stream))
          ((eq value :null) (write-string "null" stream))
          ((stringp value) (write-json-string value stream))
          ((realp value) (write-json-number value stream))
          ((vectorp value)
           (items #\[ #\] (coerce value 'list)
                  (lambda (item) (write-json item stream indent sort-keys (1+ level)))))
          ((and (consp value) (eq :object (car value)))
           (items #\{ #\}
                  (if sort-keys
                      (sort (copy-list (cdr value)) #'string< :key #'car)
                      (cdr value))
                  (lambda (pair)
                    (write-json-string (car pair) stream)
                    (write-string ": " stream)
                    (write-json (cdr pair) stream indent sort-keys (1+ level)))))
          (t (fail "Cannot encode ~S as JSON" value)))))

(defun json-string (value &key (indent 2) sort-keys)
  "Encode VALUE; INDENT NIL gives one line with \", \" and \": \" separators."
  (with-output-to-string (stream)
    (write-json value stream indent sort-keys 0)))

(defun json-write-file (path value &key (indent 2))
  (write-text path (concatenate 'string (json-string value :indent indent) (string #\Newline))))
