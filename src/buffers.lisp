(in-package #:libtmux.internal)

(defparameter *buffer-row-spec*
  (make-row-spec :buffer "buffer/1" '("list-buffers")
                 (vector (make-field-spec :buffer/name :buffer :text :format "buffer_name")
                         (make-field-spec :buffer/size :buffer :integer :format "buffer_size"
                                          :minimum 0 :maximum 18446744073709551615)
                         (make-field-spec :buffer/created :buffer :integer :format "buffer_created"
                                          :minimum -9223372036854775808 :maximum 9223372036854775807))))

(defun buffer-name-arguments (name &key create)
  (when name
    (let ((name (text-argument name "Buffer name" nil)))
      (when (and create
                 (find-if (lambda (character)
                            (or (< (char-code character) 32)
                                (= (char-code character) 127)
                                (char= character #\\)))
                          name))
        (invalid-argument "New buffer names cannot contain backslashes, ASCII controls or DEL"))
      (list "-b" name))))

(defun buffer-file-argument (path)
  (let ((path (text-argument path "Buffer file path" nil)))
    (when (string= path "-")
      (invalid-argument "Use set-buffer or show-buffer for bytes; spell a file named - as ./-"))
    (literal-format path)))

(defun decode-outcome-rows (client outcome spec cancel-token timeout row-limit)
  (handler-bind ((libtmux:libtmux-error
                   (lambda (condition)
                     (setf (slot-value condition 'libtmux::client) client
                           (slot-value condition 'libtmux::outcome) outcome))))
    (let ((budget (make-capture-budget
                   :deadline (+ (monotonic-seconds)
                                (- (or timeout (slot-value client 'libtmux::timeout))
                                   (libtmux:outcome-elapsed outcome)))))
          (token (or cancel-token (libtmux:make-cancellation-token))))
      (decode-rows spec (slot-value outcome 'libtmux::stdout) :row-limit row-limit
                   :check-budget (lambda () (check-capture-budget budget token))))))

(in-package #:libtmux)

(defun list-buffers (client &key (row-limit 10000) cancel-token timeout output-limit)
  "Acquire buffer metadata; return a fresh simple vector of owned plists and an outcome.
Each plist has :BUFFER/NAME, :BUFFER/SIZE (bytes) and :BUFFER/CREATED (Unix
seconds). Preserve tmux's listing order; buffer names are mutable locators,
not captured entity identities. Empty listing returns #(). ROW-LIMIT bounds
decoding. Signals an operational or decoding condition with the raw outcome."
  (unless (typep row-limit '(integer 1))
    (libtmux.internal::invalid-argument "Buffer row limit must be positive"))
  (let* ((spec libtmux.internal::*buffer-row-spec*)
         (outcome (libtmux.internal::perform-command
                   client nil (list "list-buffers" "-F" (libtmux.internal::row-format spec))
                   :cancel-token cancel-token :timeout timeout :output-limit output-limit))
         (rows (libtmux.internal::decode-outcome-rows client outcome spec cancel-token timeout row-limit)))
    (values (map 'vector
                 (lambda (row)
                   (loop for field across (libtmux.internal::row-spec-fields spec)
                         append (list (libtmux.internal::field-spec-key field)
                                      (libtmux.internal::row-value row (libtmux.internal::field-spec-key field)))))
                 rows) outcome)))

(defun set-buffer (client data &key name append cancel-token timeout output-limit)
  "Store literal DATA in a named or automatic buffer; return a COMMAND-OUTCOME.
DATA is a NUL-free string or an octet vector. Strings use tmux set-buffer;
octets use its load-buffer stdin path and preserve NUL and invalid UTF-8.
APPEND is available only for strings. Empty DATA is tmux's no-op and preserves
an existing buffer. NAME is literal; omission creates an automatic name.
New names reject backslashes, ASCII controls and DEL before I/O because tmux
versions otherwise rewrite or reject them. Spaces and Unicode are supported.
Signals INVALID-ARGUMENT or an operational condition."
  (let ((names (libtmux.internal::buffer-name-arguments name :create t)))
    (if (stringp data)
        (libtmux.internal::perform-command
         client nil (append '("set-buffer") names (when append '("-a"))
                            (list "--" (libtmux.internal::text-argument data "Buffer text")))
         :cancel-token cancel-token :timeout timeout :output-limit output-limit)
        (progn
          (unless (vectorp data) (libtmux.internal::invalid-argument "Buffer data must be a string or octet vector"))
          (when append (libtmux.internal::invalid-argument "Appending octets is not supported; use an explicit replacement"))
          (libtmux.internal::perform-command
           client nil (append '("load-buffer") names '("--" "-"))
           :input (libtmux.internal::octet-vector data)
           :cancel-token cancel-token :timeout timeout :output-limit output-limit)))))

(defun show-buffer (client &key name cancel-token timeout output-limit)
  "Read a literal named buffer, or tmux's top buffer; return octets and an outcome.
Output is an owned octet vector with no text decoding or trimming. Uses an
ordinary unattached tmux client and requires normal completion with empty stderr.
Names select the buffer at dispatch, not an earlier incarnation. A post-launch
failure does not prove non-dispatch. Signals an operational condition retaining
its outcome and any partial bytes."
  (let ((outcome (libtmux.internal::perform-command
                  client nil (append '("show-buffer") (libtmux.internal::buffer-name-arguments name))
                  :raw-read t :cancel-token cancel-token :timeout timeout :output-limit output-limit)))
    (values (outcome-stdout outcome) outcome)))

(defun load-buffer (client path &key name cancel-token timeout output-limit)
  "Load a file's bytes into a literal named or automatic buffer; return an outcome.
PATH is literal path text, not a format. Relative paths follow the tmux command
client's cwd. An empty file is tmux's no-op and preserves an existing buffer.
New names reject backslashes, ASCII controls and DEL before I/O.
Use SET-BUFFER for in-memory bytes. Signals INVALID-ARGUMENT or an operational
condition; a failure after dispatch may have an uncertain outcome."
  (libtmux.internal::perform-command
   client nil (append '("load-buffer") (libtmux.internal::buffer-name-arguments name :create t)
                      (list "--" (libtmux.internal::buffer-file-argument path)))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun save-buffer (client path &key name append cancel-token timeout output-limit)
  "Save a named or top buffer's bytes to literal PATH; return a COMMAND-OUTCOME.
Overwrite the file unless APPEND is true. Relative paths follow tmux's command
client cwd. Use SHOW-BUFFER for returned bytes. Success records tmux's reported
completion, not independently verified file contents or durability. In particular,
tmux 3.3a can suppress file-write errors. An uncertain write is never retried.
Signals INVALID-ARGUMENT or an operational condition."
  (libtmux.internal::perform-command
   client nil (append '("save-buffer") (libtmux.internal::buffer-name-arguments name)
                      (when append '("-a")) (list "--" (libtmux.internal::buffer-file-argument path)))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun paste-buffer (client pane &key name separator raw bracketed verbatim delete
                                     cancel-token timeout output-limit)
  "Paste a named or top buffer into PANE; return a COMMAND-OUTCOME.
Newlines become Return by default. RAW preserves newlines; SEPARATOR explicitly
replaces each newline with literal text and is mutually exclusive with RAW.
VERBATIM preserves every byte, implies RAW and disables tmux's newer control-byte
sanitization; it cannot be combined with a separator or bracket markers.
BRACKETED uses bracketed paste when the pane enabled it. DELETE removes the
selected buffer afterward. Tmux may accept without sending when input is
disabled; success does not prove application consumption. Signals STALE-TARGET
or an operational condition."
  (when (and raw separator) (libtmux.internal::invalid-argument "Choose raw paste or a separator"))
  (when (and verbatim (or separator bracketed))
    (libtmux.internal::invalid-argument "Verbatim paste cannot add a separator or bracket markers"))
  (libtmux.internal::perform-command
   client (list pane)
   (append (list "paste-buffer" "-t" (libtmux.internal::physical-target pane :pane))
           (libtmux.internal::buffer-name-arguments name)
           (when separator (list "-s" (libtmux.internal::text-argument separator "Paste separator")))
           (when (or raw verbatim) '("-r")) (when bracketed '("-p")) (when delete '("-d")))
   :version-flags (when verbatim '(("3.7" "-S")))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun delete-buffer (client &key name cancel-token timeout output-limit)
  "Delete the literal named buffer, or the current top buffer; return an outcome.
Named deletion requires a live tmux 3.4+ daemon because 3.3a can delete the top
buffer when the supplied name is missing. On 3.3a, an explicit NAME signals
UNSUPPORTED-CAPABILITY before payload dispatch; omission still deletes the top
buffer. A name identifies the buffer at dispatch, not an earlier incarnation.
Signals an operational condition on failure; never retries an unknown deletion."
  (libtmux.internal::perform-command
   client nil (append '("delete-buffer") (libtmux.internal::buffer-name-arguments name))
   :minimum-version (when name "3.4") :feature :named-buffer-deletion
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))
