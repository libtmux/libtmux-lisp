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
                                "''" "" "λ%2509%09%0A%0D\\,#{pid}" "0" "1" "")))
         (row (aref (libtmux.internal::decode-rows :pane bytes) 0)))
    (is (equal "%3" (libtmux.internal::row-value row :pane/id)))
    (is (equal '(nil t) (multiple-value-list (libtmux.internal::row-value row :pane/active))))
    (is (equal '(nil nil) (multiple-value-list (libtmux.internal::row-value row :pane/pid))))
    (is (equal '(nil nil) (multiple-value-list (libtmux.internal::row-value row :pane/current-path))))
    (is (equal "''" (libtmux.internal::row-value row :pane/current-command)))
    (is (equal (format nil "λ%09~C~C~C\\,#{pid}" #\Tab #\Newline #\Return)
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
