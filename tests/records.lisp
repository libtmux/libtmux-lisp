(in-package #:libtmux.tests)

(in-suite unit)

(defun record-bytes (fields)
  (libtmux.internal::encode-utf8
   (with-output-to-string (stream)
     (loop for field in fields for first = t then nil
           do (unless first (write-char #\Tab stream)) (write-string field stream))
     (terpri stream))))

(test record-codec-preserves-text-and-presence
  (let* ((bytes (record-bytes '("pane/1" "$1" "0" "@2" "%253" "0" "0" "10" "20"
                                "''" "" "λ%2509%09%0A%0D\\,#{pid}%24HOME%01%7F" "0" "1" "")))
         (row (aref (libtmux.internal::decode-rows :pane bytes) 0)))
    (is (equal "%3" (libtmux.internal::row-value row :pane/id)))
    (is (equal '(nil t) (multiple-value-list (libtmux.internal::row-value row :pane/active))))
    (is (equal '(nil nil) (multiple-value-list (libtmux.internal::row-value row :pane/pid))))
    (is (equal '(nil nil) (multiple-value-list (libtmux.internal::row-value row :pane/current-path))))
    (is (equal "''" (libtmux.internal::row-value row :pane/current-command)))
    (is (equal (format nil "λ%09~C~C~C\\,#{pid}$HOME~C~C"
                       #\Tab #\Newline #\Return (code-char 1) (code-char 127))
               (libtmux.internal::row-value row :pane/title)))
    (is (equal '("" t) (multiple-value-list (libtmux.internal::row-value row :pane/start-command))))
    (fill bytes 0)
    (is (equal "%3" (libtmux.internal::row-value row :pane/id))))
  (let ((row (aref (libtmux.internal::decode-rows
                   :session (record-bytes '("session/1" "$0" "" "" "0" "1"))) 0)))
    (is (equal '("" t) (multiple-value-list (libtmux.internal::row-value row :session/name))))
    (is (equal '(nil nil) (multiple-value-list (libtmux.internal::row-value row :session/created))))))

(test malformed-records-and-scalar-bounds
  (dolist (fields '(("session/1" "$0" "name" "1" "0" "1" "extra")
                    ("session/1" "$-1" "name" "1" "0" "1")
                    ("session/1" "$0" "bad%zz" "1" "0" "1")
                    ("session/1" "$0" "bad%0" "1" "0" "1")
                    ("session/1" "$0" "bad%00" "1" "0" "1")
                    ("session/1" "$0" "bad%20" "1" "0" "1")
                    ("session/1" "$0" "bad%2f" "1" "0" "1")
                    ("session/1" "$0" "bad%FF" "1" "0" "1")
                    ("session/1" "$0" "name" "1" "0.5" "1")
                    ("session/1" "$0" "name" "1" "4294967296" "1")
                    ("session/1" "$0" "name" "1" "" "1")))
    (signals libtmux:decoding-error
      (libtmux.internal::decode-rows :session (record-bytes fields))))
  (signals libtmux:decoding-error
    (libtmux.internal::decode-scalar (libtmux.internal::registered-field :pane/active :pane) ""))
  (signals libtmux:decoding-error
    (libtmux.internal::decode-rows :session (libtmux.internal::encode-utf8 "session/1")))
  (signals libtmux:decoding-error
    (libtmux.internal::unescape-field (libtmux.internal::octet-vector #(255)) 0 1))
  (signals libtmux:decoding-error
    (libtmux.internal::unescape-field (libtmux.internal::octet-vector #(65 0 66)) 0 3))
  (signals libtmux:output-limit-exceeded
    (libtmux.internal::decode-rows :session
      (record-bytes '("session/1" "$0" "name" "1" "0" "1")) :row-limit 0))
  (signals libtmux:output-limit-exceeded
    (libtmux.internal::decode-rows :session
      (record-bytes '("session/1" "$0" "name" "1" "0" "1")) :field-limit 3)))

(defun listing-batch-fixture ()
  (mapcar #'record-bytes
          '(("w/links/1" "321" "42" "/s" "3.8")
            ("window-link/1" "$0" "0" "@0" "name" "80" "24" "1" "1" "layout")
            ("w/panes/1" "321" "42" "/s" "3.8")
            ("pane/1" "$0" "0" "@0" "%250" "0" "1" "80" "24" "cat"
             "/tmp" "title" "123" "0" "")
            ("w/clnts/1" "321" "42" "/s" "3.8")
            ("client/1" "tty1" "124" "42" "tty1" "$0" "0" "0"))))

(test listing-batch-preserves-separate-witnesses-and-limits
  (let ((blocks (listing-batch-fixture)))
    (dolist (client-present '(nil t))
      (let ((witnesses nil))
        (let ((rows (multiple-value-list
                     (libtmux.internal::decode-listing-batch
                      (apply #'concatenate '(vector (unsigned-byte 8))
                             (subseq blocks 0 (if client-present 6 5)))
                      (lambda (rows)
                        (push (libtmux.internal::row-value (aref rows 0) :server/pid)
                              witnesses))
                      :row-limit 1 :field-limit 13))))
          (is (equal '(321 321 321) witnesses))
          (is (equal (list 1 1 (if client-present 1 0)) (mapcar #'length rows)))
          (is (equal "%0" (libtmux.internal::row-value (aref (second rows) 0) :pane/id))))))
    (let ((prefixes (apply #'concatenate '(vector (unsigned-byte 8))
                           (list (first blocks) (third blocks) (fifth blocks)))))
      (is (every #'zerop
                 (mapcar #'length
                         (multiple-value-list
                          (libtmux.internal::decode-listing-batch
                           prefixes #'identity :field-limit 9)))))
      (signals libtmux:output-limit-exceeded
        (libtmux.internal::decode-listing-batch prefixes #'identity :field-limit 8)))
    (signals libtmux:output-limit-exceeded
      (libtmux.internal::decode-listing-batch
       (apply #'concatenate '(vector (unsigned-byte 8))
              (append (subseq blocks 0 4) (list (fourth blocks)) (subseq blocks 4)))
       #'identity :row-limit 1))
    (let ((checks 0))
      (signals libtmux:command-cancelled
        (libtmux.internal::decode-listing-batch
         (apply #'concatenate '(vector (unsigned-byte 8)) blocks) #'identity
         :check-budget (lambda ()
                         (when (= 2 (incf checks))
                           (error 'libtmux:command-cancelled :message "Cancelled decode"))))))
    (is (< (loop for argument in (libtmux.internal::listing-batch-command)
                 sum (1+ (length (libtmux.internal::encode-utf8 argument))))
           16000))))

(test listing-batch-rejects-invalid-framing
  (let ((blocks (listing-batch-fixture)))
    (dolist (invalid
             (list (rest blocks)
                   (append (list (first blocks)) blocks)
                   (append (list (third blocks)) (rest blocks))
                   (append (subseq blocks 0 2) (subseq blocks 3))
                   (append blocks (list (first blocks)))
                   (append (subseq blocks 0 3)
                           (list (record-bytes '("pane/1" "wrong-columns")))
                           (subseq blocks 4))
                   (append blocks (list (record-bytes '("unexpected"))))))
      (signals libtmux:decoding-error
        (libtmux.internal::decode-listing-batch
         (apply #'concatenate '(vector (unsigned-byte 8)) invalid) #'identity)))
    (dolist (count '(0 2 4))
      (signals libtmux:incomplete-snapshot
        (libtmux.internal::decode-listing-batch
         (apply #'concatenate '(vector (unsigned-byte 8)) (subseq blocks 0 count))
         #'identity)))
    (let ((bytes (apply #'concatenate '(vector (unsigned-byte 8)) blocks)))
      (signals libtmux:decoding-error
        (libtmux.internal::decode-listing-batch
         (subseq bytes 0 (1- (length bytes))) #'identity)))))
