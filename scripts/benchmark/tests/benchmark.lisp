(in-package #:libtmux.tests)

(in-suite scripts)

(test benchmark-tail-is-not-reported-from-six-samples
  (let ((result (libtmux.scripts.benchmark:summarize '(1 2 3 4 5 6))))
    (is (= 7/2 (libtmux.scripts:jref result "median")))
    (is (eq :null (libtmux.scripts:jref result "p95")))
    (is (equalp result (libtmux.scripts.benchmark:summarize '(1 2 3 4 5 6))))
    (is (= 19 (libtmux.scripts:jref
               (libtmux.scripts.benchmark:summarize (loop for i from 1 to 20 collect i)) "p95")))))

(test partial-or-duplicate-benchmark-sample-sets-are-not-results
  (flet ((samples (n) (loop for i below n collect (libtmux.scripts:obj "phase" "subprocess" "iteration" i))))
    (let ((complete (samples 6)))
      (libtmux.scripts.benchmark:validate-samples complete '("subprocess") 6)
      (dolist (broken (list (butlast complete) (append complete (list (first complete)))
                            (append (butlast complete) (list (first complete)))))
        (signals libtmux.scripts:script-failure
          (libtmux.scripts.benchmark:validate-samples broken '("subprocess") 6))))))

(defun tsv (&rest fields)
  (format nil "~{~A~^~C~}" (loop for (field . more) on fields collect field when more collect #\Tab)))

(defparameter *benchmark-rows*
  (append (list (tsv "meta" "sbcl" "2.6.10") (tsv "meta" "asdf" "3.3.7") (tsv "meta" "tmux" "3.3a")
                (tsv "meta" "control" "unsupported-before-3.7") (tsv "meta" "clock" "monotonic")
                (tsv "meta" "clock-units-per-second" "1000000000")
                (tsv "setup" "fixture" "0" "0.1" "10" "9" "-"))
          (loop for (phase payload launches) in '(("subprocess" "514" "2") ("snapshot" "-" "1"))
                append (loop for i below 6
                             collect (tsv "sample" phase (princ-to-string i) "0.01" "10" launches payload)))
          (list (tsv "cleanup" "fixture" "PASS"))))

(defun read-benchmark-rows (rows)
  (libtmux.scripts:with-temporary-directory (directory "libtmux-benchmark")
    (let ((path (merge-pathnames "records.tsv" directory)))
      (libtmux.scripts:write-text path (format nil "~{~A~%~}" rows))
      (libtmux.scripts.benchmark:read-records path 6 2))))

(defun replace-in-rows (rows old new)
  (mapcar (lambda (row) (cl-ppcre:regex-replace-all (cl-ppcre:quote-meta-chars old) row new)) rows))

(test benchmark-records-require-cleanup-setup-and-identical-payloads
  (let ((rows *benchmark-rows*))
    (is (= 12 (length (nth-value 1 (read-benchmark-rows rows)))))
    (is (= 12 (length (nth-value 1 (read-benchmark-rows
                                    (replace-in-rows rows "unsupported-before-3.7"
                                                     "unsupported-before-3.8"))))))
    (dolist (broken (list (replace-in-rows rows (tsv "" "514") (tsv "" "513"))
                          (butlast rows)
                          (remove (nth 6 rows) rows :test #'string=)
                          (replace-in-rows rows "0.01" "0.0")
                          (replace-in-rows rows (tsv "" "2" "514") (tsv "" "0" "514"))))
      (signals libtmux.scripts:script-failure (read-benchmark-rows broken)))))

(test overlapping-benchmark-intervals-do-not-claim-a-speedup
  (flet ((interval (median low high)
           (libtmux.scripts:obj "median" median "median_ci95" (vector low high))))
    (is (equalp (libtmux.scripts:obj "status" "unresolved" "ratio" :null)
                (libtmux.scripts.benchmark:compare (interval 2 1 4) (interval 1 1/2 3))))
    (is (equalp (libtmux.scripts:obj "status" "separated" "ratio" 4)
                (libtmux.scripts.benchmark:compare (interval 4 3 5) (interval 1 1/2 2))))))
