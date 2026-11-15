;;; Extract the pinned tmux option schema, rejecting unrecognized C declarations.
;;;
;;;   sbcl --script scripts/options-catalog/extract-options-catalog.lisp \
;;;       --tmux-source PATH [--cc cc] [--output DIR]
;;;
;;; PATH is a tmux Git checkout that holds the commits in tools/tmux-sources.json.
;;; The host C preprocessor expands upstream hook and string macros, a restricted
;;; initializer reader extracts the schema, and a separately compiled C view
;;; (compiled-schema.c) checks every extracted field. Source defaults are
;;; deliberately outside the schema. The script reads Git objects only; it
;;; compiles with the host `cc` and installs nothing. The catalog and its
;;; evidence go under build/options-catalog/. Feed catalog.json to
;;; `options-catalog.lisp import`. Run it outside the inner and mid loops.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))
(unless (find-package "CL-PPCRE")
  (asdf:load-system "cl-ppcre"))

(defpackage #:libtmux.scripts.extract-options-catalog
  (:use #:cl #:libtmux.scripts)
  (:export #:unsupported #:lex #:integer-value #:c-string #:symbolic-bits #:parse-table
           #:rejected-construct-checks))

(in-package #:libtmux.scripts.extract-options-catalog)

(defparameter *here* (and *load-truename* (make-pathname :name nil :type nil :defaults *load-truename*)))

(define-condition unsupported (script-failure) ())

(defun ensure (ok control &rest arguments)
  (unless ok
    (error 'unsupported :message (apply #'format nil control arguments))))

(defparameter *files* '("options-table.c" "tmux.h" "options.c" "cmd-show-options.c"
                        "cmd-set-option.c" "key-string.c" "colour.c"))
(defparameter *fields* '("name" "alternative_name" "type" "scope" "flags" "minimum" "maximum"
                         "choices" "default_str" "default_num" "default_arr" "separator"
                         "pattern" "text" "unit"))
(defparameter *default-fields* '("default_str" "default_num" "default_arr"))
(defparameter *types* '("STRING" "NUMBER" "KEY" "COLOUR" "FLAG" "CHOICE" "COMMAND"))
(defparameter *scopes* '(("OPTIONS_TABLE_SERVER" . "server") ("OPTIONS_TABLE_SESSION" . "session")
                         ("OPTIONS_TABLE_WINDOW" . "window") ("OPTIONS_TABLE_PANE" . "pane")))
(defparameter *flags* '(("OPTIONS_TABLE_IS_ARRAY" . "array") ("OPTIONS_TABLE_IS_HOOK" . "hook")
                        ("OPTIONS_TABLE_IS_STYLE" . "style") ("OPTIONS_TABLE_IS_COLOUR" . "colour")))
(defparameter *representations*
  '(("string" . "string") ("number" . "integer") ("key" . "tmux-key-string")
    ("colour" . "tmux-colour-string") ("flag" . "boolean") ("choice" . "choice-string")
    ("command" . "tmux-command-source")))
(defparameter *native-scopes*
  '(("server" "server") ("session" "global-session" "session")
    ("window" "global-window" "window") ("pane" "pane")))

;;; Lexing and reading C initializers

(defparameter *token*
  (cl-ppcre:create-scanner
   "(?s)\\s+|\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|[A-Za-z_][A-Za-z_0-9]*|0[xX][0-9a-fA-F]+[uUlL]*|[0-9]+[uUlL]*|<<|>>|[{}\\[\\]().,;=|+*\\-]"))

(defun lex (text)
  (let ((tokens '()) (position 0))
    (loop while (< position (length text))
          do (multiple-value-bind (start end) (cl-ppcre:scan *token* text :start position)
               (ensure (and start (= start position)) "unsupported C token at byte ~D: ~S"
                       position (subseq text position (min (length text) (+ position 60))))
               (unless (every (lambda (c) (member c '(#\Space #\Tab #\Newline #\Return #\Page #\Vt)))
                              (subseq text start end))
                 (push (subseq text start end) tokens))
               (setf position end)))
    (coerce (nreverse tokens) 'simple-vector)))

(defstruct (reader (:constructor make-reader (tokens))) tokens (position 0))

(defun peek (reader)
  (and (< (reader-position reader) (length (reader-tokens reader)))
       (aref (reader-tokens reader) (reader-position reader))))

(defun take (reader &optional expected)
  (let ((value (peek reader)))
    (ensure value "unexpected end of C initializer")
    (when expected
      (ensure (string= value expected) "expected ~S, received ~S at token ~D"
              expected value (reader-position reader)))
    (incf (reader-position reader))
    value))

(defun expression (reader terminators)
  (let ((result '()) (stack '()))
    (loop while (peek reader)
          do (let ((token (peek reader)))
               (when (and (null stack) (member token terminators :test #'string=)) (return))
               (take reader)
               (cond ((member token '("(" "[" "{") :test #'string=) (push token stack))
                     ((member token '(")" "]" "}") :test #'string=)
                      (ensure (and stack (string= (pop stack)
                                                  (cond ((string= token ")") "(")
                                                        ((string= token "]") "[")
                                                        (t "{"))))
                              "unbalanced C initializer")))
               (push token result)))
    (ensure (and result (null stack)) "empty or unbalanced C expression")
    (nreverse result)))

(defun c-string (tokens)
  "Decode concatenated C string literals; return NIL for NULL."
  (if (equal tokens '("NULL"))
      nil
      (let ((out (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
        (dolist (token tokens)
          (ensure (and (> (length token) 1) (char= #\" (char token 0))
                       (char= #\" (char token (1- (length token)))))
                  "unsupported C string expression: ~S" tokens)
          (let ((value (subseq token 1 (1- (length token)))) (i 0))
            (loop while (< i (length value))
                  do (let ((c (char value i)))
                       (incf i)
                       (if (char/= c #\\)
                           (loop for octet across (sb-ext:string-to-octets (string c) :external-format :utf-8)
                                 do (vector-push-extend octet out))
                           (progn
                             (ensure (< i (length value)) "trailing C string escape")
                             (setf c (char value i))
                             (incf i)
                             (let ((simple (assoc c '((#\a . 7) (#\b . 8) (#\f . 12) (#\n . 10)
                                                      (#\r . 13) (#\t . 9) (#\v . 11) (#\\ . 92)
                                                      (#\" . 34) (#\' . 39) (#\? . 63)))))
                               (cond (simple (vector-push-extend (cdr simple) out))
                                     ((digit-char-p c 8)
                                      (let ((digits (string c)))
                                        (loop while (and (< (length digits) 3) (< i (length value))
                                                         (digit-char-p (char value i) 8))
                                              do (setf digits (concatenate 'string digits
                                                                           (string (char value i))))
                                                 (incf i))
                                        (let ((n (parse-integer digits :radix 8)))
                                          (ensure (<= n 255) "C octal escape exceeds one byte")
                                          (vector-push-extend n out))))
                                     ((char= c #\x)
                                      (let ((start i))
                                        (loop while (and (< i (length value))
                                                         (digit-char-p (char value i) 16))
                                              do (incf i))
                                        (ensure (> i start) "empty C hex escape")
                                        (let ((n (parse-integer value :start start :end i :radix 16)))
                                          (ensure (<= n 255) "C hex escape exceeds one byte")
                                          (vector-push-extend n out))))
                                     (t (ensure nil "unsupported C escape: ~S" c))))))))))
        (ensure (not (find 0 out)) "embedded NUL in schema string")
        (sb-ext:octets-to-string (coerce out '(simple-array (unsigned-byte 8) (*)))
                                 :external-format :utf-8))))

(defun integer-value (tokens)
  "Evaluate a restricted C integer constant expression."
  (let ((reader (make-reader (coerce tokens 'simple-vector)))
        (precedence '(("|" . 1) ("<<" . 2) (">>" . 2) ("+" . 3) ("-" . 3) ("*" . 4))))
    (labels ((operator-precedence (token) (cdr (assoc token precedence :test #'equal)))
             (parse (&optional (minimum 0))
               (let* ((token (take reader))
                      (value
                        (cond ((string= token "(") (prog1 (parse) (take reader ")")))
                              ((member token '("+" "-") :test #'string=)
                               (let ((operand (parse 5))) (if (string= token "-") (- operand) operand)))
                              (t (ensure (cl-ppcre:scan "^(?:0[xX][0-9a-fA-F]+|0|[1-9][0-9]*)[uUlL]*$" token)
                                         "unsupported integer expression: ~S" tokens)
                                 (let ((literal (string-right-trim "uUlL" token)))
                                   (if (and (> (length literal) 1) (char-equal #\x (char literal 1)))
                                       (parse-integer literal :start 2 :radix 16)
                                       (parse-integer literal)))))))
                 (loop for operator = (peek reader)
                       for level = (and operator (operator-precedence operator))
                       while (and level (>= level minimum))
                       do (take reader)
                          (let ((right (parse (1+ level))))
                            (cond ((string= operator "+") (incf value right))
                                  ((string= operator "-") (decf value right))
                                  ((string= operator "*") (setf value (* value right)))
                                  ((string= operator "|") (setf value (logior value right)))
                                  (t (ensure (<= 0 right 63) "unbounded C shift")
                                     (setf value (if (string= operator "<<")
                                                     (ash value right)
                                                     (ash value (- right))))))
                            (ensure (< (abs value) (expt 2 64))
                                    "integer expression exceeds extraction profile")))
                 value)))
      (let ((value (parse)))
        (ensure (null (peek reader)) "unconsumed integer expression: ~S" tokens)
        value))))

(defun symbolic-bits (tokens allowed)
  "Return the names in TOKENS, an OR of schema constants drawn from ALLOWED."
  (when tokens
    (ensure (oddp (length tokens)) "bad bit expression: ~S" tokens)
    (let ((result '()))
      (loop for token in tokens for index from 0
            do (if (oddp index)
                   (ensure (string= token "|") "unsupported bit operator: ~A" token)
                   (progn
                     (ensure (assoc token allowed :test #'string=)
                             "unknown schema flag/scope: ~A" token)
                     (ensure (not (member token result :test #'string=))
                             "repeated schema flag/scope: ~A" token)
                     (push token result))))
      (nreverse result))))

(defun parse-table (text)
  "Parse the preprocessed options table; return arrays, array declarations, entries, aliases.
Entries are alists from field name to token list, in source order."
  (let* ((prelude (format nil "#pragma GCC diagnostic push~%#pragma GCC diagnostic ignored \"-Wpedantic\"~%#pragma GCC diagnostic pop~%"))
         (text (if (uiop:string-prefix-p prelude text) (subseq text (length prelude)) text))
         (reader (make-reader (lex text)))
         (arrays '()) (declarations '()) (entries :none) (aliases :none))
    (loop while (peek reader)
          do (let ((start (reader-position reader)))
               (if (string= "static" (peek reader))
                   (progn
                     (dolist (token '("static" "const" "char" "*")) (take reader token))
                     (let ((name (take reader)) (values '()))
                       (ensure (cl-ppcre:scan "^options_table_[a-z_0-9]+$" name) "unknown static table: ~A" name)
                       (dolist (token '("[" "]" "=" "{")) (take reader token))
                       (loop until (equal "}" (peek reader))
                             do (push (c-string (expression reader '("," "}"))) values)
                                (when (equal "," (peek reader)) (take reader ",")))
                       (take reader "}") (take reader ";")
                       (setf values (nreverse values))
                       (ensure (and values (null (car (last values)))
                                    (notany #'null (butlast values)))
                               "bad NULL-terminated string table: ~A" name)
                       (ensure (not (assoc name arrays :test #'string=)) "duplicate string table: ~A" name)
                       (push (cons name (butlast values)) arrays)
                       (push (format nil "~{~A~^ ~}"
                                     (coerce (subseq (reader-tokens reader) start (reader-position reader))
                                             'list))
                             declarations)))
                   (progn
                     (dolist (token '("const" "struct")) (take reader token))
                     (let* ((kind (take reader)) (variable (take reader)) (items '()))
                       (ensure (member (list kind variable)
                                       '(("options_table_entry" "options_table")
                                         ("options_name_map" "options_other_names"))
                                       :test #'equal)
                               "unsupported declaration: ~A ~A" kind variable)
                       (dolist (token '("[" "]" "=" "{")) (take reader token))
                       (loop until (equal "}" (peek reader))
                             do (take reader "{")
                                (push (if (string= kind "options_name_map")
                                          (let ((left (c-string (expression reader '(","))))
                                                (right (progn (take reader ",")
                                                              (c-string (expression reader '("}"))))))
                                            (list left right))
                                          (let ((item '()))
                                            (loop until (equal "}" (peek reader))
                                                  do (take reader ".")
                                                     (let ((field (take reader)))
                                                       (ensure (and (member field *fields* :test #'string=)
                                                                    (not (assoc field item :test #'string=)))
                                                               "unknown/duplicate designated field: ~A" field)
                                                       (take reader "=")
                                                       (setf item (append item (list (cons field (expression reader '("," "}")))))))
                                                     (when (equal "," (peek reader)) (take reader ",")))
                                            item))
                                      items)
                                (take reader "}")
                                (when (equal "," (peek reader)) (take reader ",")))
                       (take reader "}") (take reader ";")
                       (setf items (nreverse items))
                       (if (string= kind "options_name_map")
                           (progn
                             (ensure (and (eq aliases :none) (equal (car (last items)) '(nil nil)))
                                     "bad alias sentinel/declaration")
                             (setf aliases (butlast items))
                             (ensure (every (lambda (alias) (and (first alias) (second alias))) aliases)
                                     "NULL alias before sentinel"))
                           (progn
                             (ensure (and (eq entries :none)
                                          (equal (car (last items)) '(("name" "NULL"))))
                                     "bad option sentinel/declaration")
                             (setf entries (butlast items)))))))))
    (ensure (and (not (eq entries :none)) (not (eq aliases :none))) "missing top-level table")
    (ensure (< (length entries) 4096) "too many schema nodes")
    (values (nreverse arrays) (nreverse declarations) entries aliases)))

(defun schema-header (header)
  "Return the schema section of tmux.h and an alist of its integer constants."
  (let ((section (cl-ppcre:scan-to-strings
                  "(?s)/\\* Option table entries\\. \\*/(.*?)/\\* Common command usages\\. \\*/" header)))
    (ensure section "unsupported tmux.h schema section")
    (let* ((block (nth-value 1 (cl-ppcre:scan-to-strings
                                "(?s)/\\* Option table entries\\. \\*/(.*?)/\\* Common command usages\\. \\*/"
                                header)))
           (block (aref block 0))
           (enum (nth-value 1 (cl-ppcre:scan-to-strings "(?s)enum options_table_type\\s*\\{([^}]+)\\}" block)))
           (actual (and enum
                        (remove "" (mapcar (lambda (s) (string-trim '(#\Space #\Tab #\Newline) s))
                                           (cl-ppcre:split "," (aref enum 0)))
                                :test #'string=)))
           (defines '()))
      (ensure (equal actual (mapcar (lambda (type) (concatenate 'string "OPTIONS_TABLE_" type)) *types*))
              "unknown type enum: ~S" actual)
      (cl-ppcre:do-register-groups (key value)
          ("(?m)^#define\\s+(OPTIONS_TABLE_\\w+)\\s+([^\\n]+)$" block)
        (push (cons key (integer-value (coerce (lex value) 'list))) defines))
      (setf defines (nreverse defines))
      (ensure (every (lambda (entry)
                       (or (assoc (car entry) *scopes* :test #'string=)
                           (assoc (car entry) *flags* :test #'string=)
                           (string= (car entry) "OPTIONS_TABLE_NONE")))
                     defines)
              "unknown schema bit constant")
      (ensure (every (lambda (scope) (assoc (car scope) defines :test #'string=)) *scopes*)
              "missing schema scopes")
      (values block defines))))

(defun line-for-name (source name)
  (let* ((quoted (cl-ppcre:quote-meta-chars name))
         (direct (cl-ppcre:scan (format nil "(?:\\.name\\s*=|OPTIONS_TABLE_(?:PANE_HOOK|WINDOW_HOOK|HOOK)\\s*\\()\\s*\"~A\"" quoted)
                                source)))
    (when (and (null direct) (uiop:string-prefix-p "after-" name))
      (setf direct (cl-ppcre:scan (format nil "OPTIONS_TABLE_AFTER_HOOK\\s*\\(\\s*\"~A\""
                                          (cl-ppcre:quote-meta-chars (subseq name 6)))
                                  source)))
    (ensure direct "cannot locate source entry: ~A" name)
    (1+ (count #\Newline source :end direct))))

;;; Extraction

(defun elapsed (start) (/ (round (* 1000000 (- (monotonic-seconds) start))) 1000000d0))

(defun command (argv &key input output directory)
  "Run ARGV; return its standard output text and the seconds it took."
  (let ((start (monotonic-seconds)))
    (multiple-value-bind (code out err)
        (run argv :input input :output (or output :string) :directory directory :timeout 120 :check nil)
      (ensure (eql 0 code) "command failed ~S: ~A" argv err)
      (values out (elapsed start)))))

(defun table-of (entry field) (cdr (assoc field entry :test #'string=)))

(defun contains (haystack needle) (and (search needle haystack) t))

(defun extract (pin sources work compiler)
  "Extract one pin's schema from SOURCES (file name to text); return its data and checks."
  (let* ((version (jref pin "tmux"))
         (build (merge-pathnames (format nil "generated/~A/" version) work))
         (table (gethash "options-table.c" sources))
         (header (gethash "tmux.h" sources)))
    (ensure-directories-exist build)
    (multiple-value-bind (section defines) (schema-header header)
      (let ((includes (cl-ppcre:all-matches-as-strings "(?m)^#include[^\\n]*$" table))
            (directives (remove-duplicates
                         (let ((found '()))
                           (cl-ppcre:do-register-groups (name) ("(?m)^#(\\w+)" table) (push name found))
                           found)
                         :test #'string=)))
        (ensure (equal includes '("#include <sys/types.h>" "#include <string.h>" "#include \"tmux.h\""))
                "unknown include set: ~S" includes)
        (ensure (and (= 2 (length directives)) (member "include" directives :test #'string=)
                     (member "define" directives :test #'string=))
                "unsupported conditional/source directive: ~S" directives)
        (let* ((input-buffer (cl-ppcre:all-matches-as-strings
                              "(?m)^#define\\s+INPUT_BUF_DEFAULT_SIZE\\s+[^\\n]+$" header))
               (translation (format nil "#include <limits.h>~%~{~A~^~%~}~%~A" input-buffer
                                    (cl-ppcre:regex-replace-all "(?m)^#include[^\\n]*$" table ""))))
          (ensure (<= (length input-buffer) 1) "ambiguous input buffer bound")
          (write-text (merge-pathnames "preprocess-input.c" build) translation)
          (multiple-value-bind (preprocessed preprocess-seconds)
              (command (list compiler "-E" "-P" "-std=c11" "-x" "c" "-") :input translation)
            (write-text (merge-pathnames "preprocessed.c" build) preprocessed)
            (multiple-value-bind (arrays declarations entries aliases) (parse-table preprocessed)
              (let ((names '()) (raw '()) (normalized '()) (c-entries '()))
                (dolist (entry entries)
                  (ensure (every (lambda (field) (assoc field entry :test #'string=)) '("name" "type" "scope"))
                          "entry missing required fields")
                  (let ((name (c-string (table-of entry "name"))))
                    (ensure (and name (cl-ppcre:scan "^[a-z][a-z0-9-]*$" name)
                                 (not (member name names :test #'string=)))
                            "unknown/duplicate built-in name: ~A" name)
                    (push name names)
                    (let ((type-tokens (table-of entry "type")))
                      (ensure (and (= 1 (length type-tokens))
                                   (member (first type-tokens)
                                           (mapcar (lambda (type) (concatenate 'string "OPTIONS_TABLE_" type)) *types*)
                                           :test #'string=))
                              "unknown type: ~S" type-tokens)
                      (let* ((type-name (string-downcase (subseq (first type-tokens) (length "OPTIONS_TABLE_"))))
                             (scope-names (symbolic-bits (table-of entry "scope") *scopes*))
                             (flag-names (symbolic-bits (table-of entry "flags") *flags*))
                             (minimum (integer-value (or (table-of entry "minimum") '("0"))))
                             (maximum (integer-value (or (table-of entry "maximum") '("0"))))
                             (choice-values :absent) (choice-table nil))
                        (ensure (every (lambda (flag) (assoc flag defines :test #'string=)) flag-names)
                                "flag has no pinned header definition")
                        (ensure (<= 0 minimum maximum (1- (expt 2 32))) "unsupported bound/profile: ~A" name)
                        (when (string= type-name "number")
                          (ensure (and (assoc "minimum" entry :test #'string=)
                                       (assoc "maximum" entry :test #'string=))
                                  "number omits explicit bounds: ~A" name))
                        (when (assoc "choices" entry :test #'string=)
                          (let ((tokens (table-of entry "choices")))
                            (ensure (and (= 1 (length tokens)) (assoc (first tokens) arrays :test #'string=))
                                    "unknown choice table: ~A" name)
                            (setf choice-table (first tokens)
                                  choice-values (cdr (assoc choice-table arrays :test #'string=)))))
                        (ensure (eq (string= type-name "choice") (not (eq choice-values :absent)))
                                "choice/type disagreement: ~A" name)
                        (let* ((choices (if (eq choice-values :absent) :null (coerce choice-values 'vector)))
                               (row (list :name name
                                          :type (position (string-upcase type-name) *types* :test #'string=)
                                          :scope (reduce #'+ (mapcar (lambda (s) (cdr (assoc s defines :test #'string=))) scope-names))
                                          :flags (reduce #'+ (mapcar (lambda (s) (cdr (assoc s defines :test #'string=))) flag-names))
                                          :minimum minimum :maximum maximum :choices choices))
                               (strings (loop for field in '("alternative_name" "separator" "pattern" "text" "unit")
                                              collect (or (c-string (or (table-of entry field) '("NULL"))) :null)))
                               (scopes (mapcar (lambda (s) (cdr (assoc s *scopes* :test #'string=))) scope-names))
                               (hook (and (member "OPTIONS_TABLE_IS_HOOK" flag-names :test #'string=) t))
                               (array (and (member "OPTIONS_TABLE_IS_ARRAY" flag-names :test #'string=) t))
                               (separator (second strings)) (pattern (third strings)))
                          (declare (ignorable separator))
                          (push (list* row strings) raw)
                          (let ((record
                                  (obj "name" name "declared_type" type-name
                                       "value_representation" (cdr (assoc type-name *representations* :test #'string=))
                                       "declared_scopes" (coerce scopes 'vector)
                                       "native_scopes" (coerce (loop for scope in scopes
                                                                     append (cdr (assoc scope *native-scopes* :test #'string=)))
                                                               'vector)
                                       "flags" (coerce (mapcar (lambda (f) (cdr (assoc f *flags* :test #'string=))) flag-names) 'vector)
                                       "array" (if array :true :false) "hook" (if hook :true :false)
                                       "minimum" (if (string= type-name "number") minimum :null)
                                       "maximum" (if (string= type-name "number") maximum :null)
                                       "choices" choices
                                       "choice_table" (or choice-table :null)
                                       "separator" (second strings) "pattern" pattern
                                       "pattern_language" (if (eq pattern :null) :null "fnmatch")
                                       "unit" (fifth strings) "description" (fourth strings)
                                       "source" (obj "file" "options-table.c" "line" (line-for-name table name)))))
                            (ensure (or (not hook) (and array (string= type-name "command")))
                                    "unknown hook representation: ~A" name)
                            (push record normalized))
                          (push (format nil "{ ~{~A~^, ~} }"
                                        (loop for (field . tokens) in entry
                                              unless (member field *default-fields* :test #'string=)
                                                collect (format nil ".~A = ~{~A~^ ~}" field tokens)))
                                c-entries))))))
                (setf names (nreverse names) raw (nreverse raw)
                      normalized (nreverse normalized) c-entries (nreverse c-entries))
                (ensure (every (lambda (alias) (member (second alias) names :test #'string=)) aliases)
                        "alias target is not a catalog entry")
                (let* ((alias-c (format nil "const struct options_name_map options_other_names[] = {~{~A~^,~}, {NULL,NULL}};"
                                        (mapcar (lambda (alias)
                                                  (format nil "{~A,~A}" (json-string (first alias) :indent nil)
                                                          (json-string (second alias) :indent nil)))
                                                aliases)))
                       (oracle-source
                         (format nil "#include <sys/types.h>~%#include <limits.h>~%#include <stddef.h>~%~A~%~{~A~^~%~}~%const struct options_table_entry options_table[] = {~%~{~A~^,~%~},~%{.name=NULL}};~%~A~%~%~A"
                                 section declarations c-entries alias-c
                                 (read-text (merge-pathnames "compiled-schema.c" *here*))))
                       (executable (merge-pathnames "schema-oracle" build))
                       (executable-name (uiop:native-namestring executable)))
                  (write-text (merge-pathnames "schema-oracle.c" build) oracle-source)
                  (multiple-value-bind (output compile-seconds)
                      (command (list compiler "-std=gnu11" "-Werror" "-O0"
                                     (uiop:native-namestring (merge-pathnames "schema-oracle.c" build))
                                     "-o" executable-name))
                    (declare (ignore output))
                    (multiple-value-bind (oracle-text execute-seconds) (command (list executable-name))
                      (let ((executable-hash (sha256-file executable)))
                        (delete-file executable)
                        (write-text (merge-pathnames "schema-oracle.json" build) oracle-text)
                        (let ((oracle (json-parse oracle-text)))
                          (ensure (json-equal (jref oracle "integer_profile")
                                              (obj "int_bits" 32 "short_bits" 16 "uint_max" 4294967295))
                                  "unsupported C ABI for numeric bounds")
                          (ensure (and (= (length raw) (length (jref oracle "options")))
                                       (every (lambda (row compiled)
                                                (destructuring-bind (row-plist &rest strings) row
                                                  (json-equal
                                                   compiled
                                                   (obj "name" (getf row-plist :name) "type" (getf row-plist :type)
                                                        "scope" (getf row-plist :scope) "flags" (getf row-plist :flags)
                                                        "minimum" (getf row-plist :minimum)
                                                        "maximum" (getf row-plist :maximum)
                                                        "choices" (getf row-plist :choices)
                                                        "alternative_name" (first strings)
                                                        "separator" (second strings) "pattern" (third strings)
                                                        "text" (fourth strings) "unit" (fifth strings)))))
                                              raw (jref oracle "options"))
                                       (json-equal (jref oracle "aliases")
                                                   (coerce (mapcar (lambda (alias)
                                                                     (vector (first alias) (second alias)))
                                                                   aliases)
                                                           'vector)))
                                  "Lisp/C schema disagreement")
                          (let* ((show (gethash "cmd-show-options.c" sources))
                                 (flags (nth-value 1 (cl-ppcre:scan-to-strings
                                                      "(?s)cmd_show_options_entry.*?\\.args = \\{ \"([^\"]+)\"" show)))
                                 (string-keys (contains (gethash "options.c" sources) "options_array_correct_key"))
                                 (capabilities
                                   (obj "show_options_format" (if (contains (aref flags 0) "F:") :true :false)
                                        "array_key_kind" (if string-keys "integer-or-string" "integer")
                                        "array_numeric_key_maximum" (if string-keys 4294967295 2147483647)
                                        "user_options" (obj "declared_type" "string"
                                                            "native_scopes" (vector "server" "global-session" "session"
                                                                                    "global-window" "window" "pane"))
                                        "user_event_hooks" (if (contains (gethash "cmd-set-option.c" sources)
                                                                         "hooks_add_event(name)")
                                                               :true :false)))
                                 (type-counts (let ((counts '()))
                                                (dolist (record normalized)
                                                  (let ((cell (assoc (jref record "declared_type") counts :test #'string=)))
                                                    (if cell (incf (cdr cell))
                                                        (push (cons (jref record "declared_type") 1) counts))))
                                                (cons :object (sort counts #'string< :key #'car)))))
                            (values
                             (obj "version" version "commit" (jref pin "commit")
                                  "integer_profile" (jref oracle "integer_profile")
                                  "capabilities" capabilities "count" (length normalized)
                                  "type_counts" type-counts
                                  "hook_count" (count :true normalized :key (lambda (r) (jref r "hook")))
                                  "array_count" (count :true normalized :key (lambda (r) (jref r "array")))
                                  "aliases" (coerce (mapcar (lambda (alias) (obj "from" (first alias) "to" (second alias)))
                                                            aliases)
                                                    'vector)
                                  "options" (coerce normalized 'vector))
                             (obj "version" version "result" "PASS" "parsed_entries" (length entries)
                                  "compiled_entries" (length (jref oracle "options"))
                                  "all_schema_fields_equal" :true
                                  "preprocess_seconds" preprocess-seconds
                                  "compile_seconds" compile-seconds
                                  "execute_seconds" execute-seconds
                                  "oracle_executable_sha256" executable-hash
                                  "oracle_executable_removed" (if (probe-file executable) :false :true)))))))))))))))))

(defun rejected-construct-checks ()
  "Prove the reader refuses constructs outside its restricted grammar; return the evidence."
  (loop for (name thunk) in
        (list (list "unknown flag" (lambda () (symbolic-bits '("OPTIONS_TABLE_IS_GUESSED") *flags*)))
              (list "function call bound" (lambda () (integer-value (coerce (lex "runtime_bound()") 'list))))
              (list "integer conditional" (lambda () (integer-value (coerce (lex "1 ? 2 : 3") 'list))))
              (list "unrecognized string prefix" (lambda () (c-string '("L" "\"wide\""))))
              (list "unrecognized C escape" (lambda () (c-string (list (format nil "\"\\q\"")))))
              (list "trailing initializer code"
                    (lambda () (parse-table "int unrelated_function(void) { return 1; }"))))
        collect (handler-case (progn (funcall thunk)
                                     (error "unsupported construct accepted: ~A" name))
                  (unsupported (condition)
                    (obj "case" name "result" "PASS" "diagnostic" (princ-to-string condition))))))

(defun utc-now ()
  (multiple-value-bind (second minute hour day month year) (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ" year month day hour minute second)))

(defun option-delta (before after)
  (let* ((left (jref before "options")) (right (jref after "options"))
         (left-names (map 'list (lambda (o) (jref o "name")) left))
         (right-names (map 'list (lambda (o) (jref o "name")) right))
         (changes '()))
    (flet ((option (options name) (find name options :key (lambda (o) (jref o "name")) :test #'string=)))
      (dolist (name (sort (intersection left-names right-names :test #'string=) #'string<))
        (let ((old (option left name)) (new (option right name)) (fields '()))
          (loop for (key . value) in (cdr new)
                unless (member key '("source" "description") :test #'string=)
                  do (unless (json-equal (jref old key) value)
                       (push (cons key (obj "before" (jref old key) "after" value)) fields)))
          (when fields
            (push (obj "name" name "fields" (cons :object (nreverse fields))) changes)))))
    (obj "from" (jref before "version") "to" (jref after "version")
         "added" (coerce (sort (set-difference right-names left-names :test #'string=) #'string<) 'vector)
         "removed" (coerce (sort (set-difference left-names right-names :test #'string=) #'string<) 'vector)
         "changed" (coerce (nreverse changes) 'vector))))

(defun extract-all (root tmux-source output compiler)
  (let* ((started (monotonic-seconds))
         (catalog-path (merge-pathnames "tools/tmux-sources.json" root))
         (pins (remove-if-not (lambda (cell) (equal "supported" (jref cell "purpose")))
                              (coerce (jref (json-read-file catalog-path) "cells") 'list)))
         (compiler-version (let ((text (command (list compiler "--version"))))
                             (subseq text 0 (or (position #\Newline text) (length text)))))
         (manifests '()) (versions '()) (verification '()))
    (ensure (= 12 (length pins)) "unexpected source pin set; review before regeneration")
    (dolist (pin pins)
      (let ((destination (merge-pathnames (format nil "sources/~A/" (jref pin "tmux")) output))
            (sources (make-hash-table :test #'equal)) (files '()))
        (ensure-directories-exist destination)
        (dolist (name *files*)
          (let ((path (merge-pathnames name destination)))
            (command (list "git" "-C" (uiop:native-namestring tmux-source) "show"
                           (format nil "~A:~A" (jref pin "commit") name))
                     :output path)
            (setf (gethash name sources) (read-text path))
            (push (cons name (obj "sha256" (sha256-file path)
                                  "url" (format nil "https://github.com/tmux/tmux/blob/~A/~A"
                                                (jref pin "commit") name)))
                  files)))
        (push (obj "version" (jref pin "tmux") "commit" (jref pin "commit")
                   "files" (cons :object (nreverse files)))
              manifests)
        (multiple-value-bind (version check) (extract pin sources output compiler)
          (push version versions)
          (push check verification))))
    (setf versions (nreverse versions) manifests (nreverse manifests) verification (nreverse verification))
    (let* ((source-hash (sha256-file catalog-path))
           (catalog (obj "schema" "libtmux.native-options-catalog/1" "status" "proposed-source-data"
                         "defaults" "Source and runtime default values are intentionally omitted; this schema describes complete built-in discovery and value contracts."
                         "source_catalog_sha256" source-hash "versions" (coerce versions 'vector)))
           (encoded (concatenate 'string (json-string catalog) (string #\Newline))))
      (write-text (merge-pathnames "catalog.json" output) encoded)
      (write-text (merge-pathnames "deltas.json" output)
                  (concatenate 'string
                               (json-string (coerce (loop for (before after) on versions while after
                                                          collect (option-delta before after))
                                                    'vector))
                               (string #\Newline)))
      (write-text (merge-pathnames "sources.json" output)
                  (concatenate 'string
                               (json-string (obj "compiler" compiler-version "source_catalog_sha256" source-hash
                                                 "records" (coerce manifests 'vector)))
                               (string #\Newline)))
      (let ((results (obj "result" "PASS" "started_utc" (utc-now)
                          "script_sha256" (sha256-file *load-truename*)
                          "catalog_sha256" (let ((path (merge-pathnames "catalog.json" output)))
                                             (sha256-file path))
                          "catalog_bytes" (length (sb-ext:string-to-octets encoded :external-format :utf-8))
                          "versions" (coerce verification 'vector)
                          "unsupported_constructs" (coerce (rejected-construct-checks) 'vector)
                          "probe_interval_seconds" (elapsed started))))
        (write-text (merge-pathnames "extraction-verification.json" output)
                    (concatenate 'string (json-string results) (string #\Newline)))
        (format t "~A~%"
                (json-string (obj "result" "PASS" "catalog_sha256" (jref results "catalog_sha256")
                                  "counts" (cons :object (mapcar (lambda (v) (cons (jref v "version") (jref v "count")))
                                                                 versions))
                                  "probe_interval_seconds" (jref results "probe_interval_seconds"))))))))

(defun main ()
  (let* ((arguments (rest sb-ext:*posix-argv*))
         (root (directory-above *load-truename* 2))
         (tmux-source (second (member "--tmux-source" arguments :test #'string=)))
         (compiler (or (second (member "--cc" arguments :test #'string=)) "cc"))
         (output (uiop:ensure-directory-pathname
                  (merge-pathnames (or (second (member "--output" arguments :test #'string=))
                                       "build/options-catalog/")
                                   root))))
    (unless tmux-source
      (fail "Usage: extract-options-catalog.lisp --tmux-source PATH [--cc cc] [--output DIR]"))
    (ensure-directories-exist output)
    (handler-bind ((error (lambda (condition)
                            (ignore-errors
                             (write-text (merge-pathnames "last-failure.json" output)
                                         (concatenate 'string
                                                      (json-string (obj "result" "FAIL"
                                                                        "error" (princ-to-string condition)))
                                                      (string #\Newline)))))))
      (extract-all root (uiop:ensure-directory-pathname (merge-pathnames tmux-source (uiop:getcwd)))
                   output compiler))
    0))

(main-when-script #'main)
