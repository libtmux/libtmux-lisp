(in-package #:libtmux.internal)

;; Byte codecs preserve wire data; the connection owner matches replies.

(defstruct (control-line-decoder (:constructor %make-control-line-decoder))
  "Private LF assembler with bounded retained storage and single-caller state."
  (line-byte-limit 1048576 :read-only t)
  (batch-byte-limit 1048576 :read-only t)
  (batch-line-limit 4096 :read-only t)
  (check-budget nil :read-only t)
  pending
  (state :open))

(defun make-control-line-decoder (&key (line-byte-limit 1048576)
                                     (batch-byte-limit 1048576)
                                     (batch-line-limit 4096) check-budget)
  "Make a private byte-line assembler; no control connection is opened.
Limits bound bytes before LF per line, wire bytes per feed, and lines per
feed. CHECK-BUDGET is an optional owner-supplied deadline/cancellation check.
The decoder requires one non-reentrant caller. It does not attribute replies."
  (unless (and (typep line-byte-limit '(integer 1))
               (typep batch-byte-limit '(integer 1))
               (typep batch-line-limit '(integer 1))
               (or (null check-budget) (functionp check-budget)))
    (invalid-argument "Control decoding limits must be positive integers and the budget check a function"))
  (%make-control-line-decoder
   :line-byte-limit line-byte-limit :batch-byte-limit batch-byte-limit
   :batch-line-limit batch-line-limit :check-budget check-budget
   :pending (make-array (min 256 line-byte-limit) :element-type '(unsigned-byte 8)
                       :adjustable t :fill-pointer 0)))

(defun check-control-decoder-open (decoder)
  (unless (and (control-line-decoder-p decoder)
               (eq :open (control-line-decoder-state decoder)))
    (invalid-argument "Control decoder must be open and idle; retire failed or finished streams")))

(defun control-decoder-check (decoder)
  (let ((check (control-line-decoder-check-budget decoder)))
    (when check (funcall check))))

(defun feed-control-lines (decoder bytes &key (start 0) (end nil end-p))
  "Assemble LF lines from a bounded octet slice; return fresh owned vectors.
Only terminating LF is removed. CR, NUL, invalid UTF-8 and guard-looking data
remain bytes. Snapshot input before budget callbacks. Invalid arguments do
not consume input; resource failures and escaping exits poison the decoder.
Per-feed limits do not bound a future owner's reply or event queues."
  (check-control-decoder-open decoder)
  (unless (typep bytes '(vector (unsigned-byte 8)))
    (invalid-argument "Control input must be an octet vector"))
  (unless end-p (setf end (length bytes)))
  (unless (and (typep start '(integer 0)) (typep end '(integer 0))
               (<= start end (length bytes)))
    (invalid-argument "Invalid control input slice"))
  (setf (control-line-decoder-state decoder) :busy)
  (let ((completed nil))
    (unwind-protect
         (progn
           (when (> (- end start) (control-line-decoder-batch-byte-limit decoder))
             (error 'libtmux:output-limit-exceeded :message "Control feed exceeds its wire byte limit"))
           (let ((input (subseq bytes start end))
                 (pending (control-line-decoder-pending decoder))
                 (limit (control-line-decoder-line-byte-limit decoder))
                 (lines nil) (count 0))
             (control-decoder-check decoder)
             (loop for index below (length input)
                   for byte = (aref input index)
                   do (when (and (plusp index) (zerop (logand index 255)))
                        (control-decoder-check decoder))
                      (cond
                        ((= byte 10)
                         (when (>= count (control-line-decoder-batch-line-limit decoder))
                           (error 'libtmux:output-limit-exceeded :message "Control feed exceeds its line limit"))
                         (push (subseq pending 0 (fill-pointer pending)) lines)
                         (incf count)
                         (setf (fill-pointer pending) 0))
                        (t
                         (when (>= (fill-pointer pending) limit)
                           (error 'libtmux:output-limit-exceeded :message "Control line exceeds its byte limit"))
                         (when (= (fill-pointer pending) (array-total-size pending))
                           (setf pending (adjust-array pending (min limit (* 2 (array-total-size pending))))
                                 (control-line-decoder-pending decoder) pending))
                         (vector-push byte pending))))
             (let ((result (coerce (nreverse lines) 'simple-vector)))
               (control-decoder-check decoder)
               (setf (control-line-decoder-state decoder) :open completed t)
               result)))
      (unless completed
        (setf (control-line-decoder-state decoder) :failed
              (control-line-decoder-pending decoder) nil)))))

(defun finish-control-lines (decoder)
  "Record clean transport EOF or signal DECODING-ERROR for a partial line.
Return a fresh empty vector on clean EOF. Neither EOF nor a decoded %exit
line proves completion of an outstanding command. Reject subsequent use."
  (check-control-decoder-open decoder)
  (setf (control-line-decoder-state decoder) :busy)
  (let ((completed nil))
    (unwind-protect
         (progn
           (control-decoder-check decoder)
           (unless (zerop (fill-pointer (control-line-decoder-pending decoder)))
             (error 'libtmux:decoding-error :message "Control stream ended within an unterminated line"))
           (let ((result (make-array 0)))
             (setf (control-line-decoder-state decoder) :closed
                   (control-line-decoder-pending decoder) nil
                   completed t)
             result))
      (unless completed
        (setf (control-line-decoder-state decoder) :failed
              (control-line-decoder-pending decoder) nil)))))

(defun decode-control-output-line (line &key (byte-limit 1048576)
                                           (line-byte-limit 1048576) check-budget)
  "Decode one notification-context pane-output line without LF, as bytes.
Return fresh octets, a fresh pane-ID string, optional age, and extended-p.
The caller must establish notification context; command output can imitate
this syntax. Reserved extended-output tokens are ignored before a colon
token. Limits bound encoded input and decoded output separately. Input is
snapshotted before budget checks; no character decoding or Lisp reader runs."
  (unless (and (typep line '(vector (unsigned-byte 8)))
               (typep byte-limit '(integer 0))
               (typep line-byte-limit '(integer 1))
               (or (null check-budget) (functionp check-budget)))
    (invalid-argument "Invalid control output bytes, limits or budget check"))
  (when (> (length line) line-byte-limit)
    (error 'libtmux:output-limit-exceeded :message "Control output line exceeds its wire byte limit"))
  (let* ((input (copy-seq line)) (end (length input)) (cursor 0) (next-check 256))
    (labels ((check () (when check-budget (funcall check-budget)))
             (malformed () (error 'libtmux:decoding-error :message "Malformed control pane-output line"))
             (peek () (and (< cursor end) (aref input cursor)))
             (take-byte ()
               (when (>= cursor end) (malformed))
               (prog1 (aref input cursor)
                 (incf cursor)
                 (when (>= cursor next-check)
                   (check)
                   (setf next-check (+ cursor 256)))))
             (literal (text)
               (map nil (lambda (char) (unless (= (char-code char) (take-byte)) (malformed))) text))
             (prefix-p (text)
               (and (<= (length text) end)
                    (loop for char across text for index from 0
                          always (= (char-code char) (aref input index)))))
             (decimal (maximum)
               (let ((start cursor) (value 0))
                 (loop for byte = (peek) while (and byte (<= 48 byte 57))
                       for digit = (- byte 48)
                       do (when (> value (floor (- maximum digit) 10)) (malformed))
                          (setf value (+ (* value 10) digit))
                          (take-byte))
                 (when (or (= start cursor)
                           (and (> (- cursor start) 1) (= 48 (aref input start))))
                   (malformed))
                 value)))
      (check)
      (let ((extended-p (cond ((prefix-p "%output ") (literal "%output ") nil)
                              ((prefix-p "%extended-output ") (literal "%extended-output ") t)
                              (t (malformed)))))
        (let ((pane-start cursor))
          (literal "%")
          (decimal #xffffffff)
          (let ((pane (map 'string #'code-char (subseq input pane-start cursor)))
                (age nil))
            (literal " ")
            (when extended-p
              (setf age (decimal #xffffffffffffffff))
              (literal " ")
              (loop
                (let ((start cursor))
                  (loop for byte = (peek) while (and byte (/= byte 32))
                        do (when (< byte 32) (malformed)) (take-byte))
                  (when (= start cursor) (malformed))
                  (let ((colon-p (and (= (- cursor start) 1) (= 58 (aref input start)))))
                    (literal " ")
                    (when colon-p (return))))))
            (let ((output (make-array (min byte-limit (- end cursor)) :element-type '(unsigned-byte 8)))
                  (used 0))
              (loop while (< cursor end)
                    for byte = (take-byte)
                    do (when (< byte 32) (malformed))
                       (when (= byte 92)
                         (setf byte 0)
                         (dotimes (index 3)
                           (let ((digit (take-byte)))
                             (unless (<= 48 digit 55) (malformed))
                             (setf byte (+ (* byte 8) (- digit 48)))))
                         (when (> byte 255) (malformed)))
                       (when (>= used byte-limit)
                         (error 'libtmux:output-limit-exceeded :message "Control pane output exceeds its decoded byte limit"))
                       (setf (aref output used) byte)
                       (incf used))
              (let ((result (subseq output 0 used)))
                (check)
                (values result pane age extended-p)))))))))
