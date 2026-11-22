;;; Compare native subprocess and control reads on an owned tmux server and keep
;;; the checked samples as durable evidence outside CI.
;;;
;;;   sbcl --script scripts/benchmark/benchmark.lisp [--program TMUX] [--samples 6..200] \
;;;       [--commands 1..32] [--panes 1..16] [--output DIR]
;;;
;;; The workload is tools/benchmark.lisp; every timed operation uses the Lisp
;;; library. This reporter runs it under scripts/test-processes, validates its
;;; records, summarizes each phase with a deterministic median bootstrap and
;;; writes report.json, records.tsv and run.log to a new directory (default
;;; dist/benchmarks/run-*). `mise run benchmark` runs it.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))

(unless (find-package "CL-PPCRE")
  (asdf:load-system "cl-ppcre"))

(defpackage #:libtmux.scripts.benchmark
  (:use #:cl #:libtmux.scripts)
  (:export #:summarize #:validate-samples #:compare #:read-records))

(in-package #:libtmux.scripts.benchmark)

(defun median (sorted)
  (let ((n (length sorted)))
    (if (oddp n)
        (aref sorted (floor n 2))
        (/ (+ (aref sorted (1- (floor n 2))) (aref sorted (floor n 2))) 2))))

(defun summarize (values)
  "Summarize at least six observations: median, 95% bootstrap interval of the median, p95.
The bootstrap is deterministic; the tail is reported from twenty observations."
  (let* ((sorted (sort (coerce values 'vector) #'<))
         (n (length sorted)))
    (when (or (< n 6) (some (lambda (x) (or (not (realp x)) (minusp x))) sorted))
      (fail "Need at least six finite nonnegative observations"))
    (let* ((state (sb-ext:seed-random-state 0))
           (medians (sort (coerce (loop repeat 2000
                                        collect (median (sort (coerce (loop repeat n
                                                                            collect (aref sorted (random n state)))
                                                                      'vector)
                                                              #'<)))
                                  'vector)
                          #'<)))
      (obj "samples" n "median" (median sorted)
           "median_ci95" (vector (aref medians 49) (aref medians 1949))
           "p95" (if (>= n 20) (aref sorted (1- (ceiling (* 95 n) 100))) :null)))))

(defun validate-samples (samples phases count)
  "Refuse partial, duplicate or unexpected sample coordinates."
  (let ((coordinates (mapcar (lambda (sample) (list (jref sample "phase") (jref sample "iteration")))
                             samples))
        (expected (loop for phase in phases append (loop for i below count collect (list phase i)))))
    (unless (and (= (length coordinates) (length expected))
                 (null (set-difference coordinates expected :test #'equal))
                 (null (set-difference expected coordinates :test #'equal)))
      (fail "Incomplete, duplicate or unexpected benchmark samples"))))

(defun compare (left right)
  "Claim a ratio only for separated median intervals of the same workload."
  (let* ((a (jref left "median_ci95")) (b (jref right "median_ci95"))
         (separated (or (> (aref a 0) (aref b 1)) (> (aref b 0) (aref a 1)))))
    (obj "status" (if separated "separated" "unresolved")
         "ratio" (if (and separated (not (zerop (jref right "median"))))
                     (/ (jref left "median") (jref right "median"))
                     :null))))

(defun number-from (text)
  (let ((*read-default-float-format* 'double-float) (*read-eval* nil))
    (handler-case (let ((value (read-from-string text)))
                    (if (realp value) value (fail "Invalid benchmark measurement")))
      (reader-error () (fail "Invalid benchmark measurement")))))

(defun read-records (path count commands)
  "Read and validate a records.tsv; return its metadata, samples and setup/cleanup timings."
  (let ((metadata '()) (samples '()) (timings '()) (clean nil))
    (dolist (line (remove "" (uiop:split-string (read-text path) :separator '(#\Newline))
                          :test #'string=))
      (let ((record (uiop:split-string line :separator '(#\Tab))))
        (cond ((and (= 3 (length record)) (string= "meta" (first record)))
               (when (assoc (second record) metadata :test #'string=)
                 (fail "Duplicate benchmark metadata"))
               (push (cons (second record) (third record)) metadata))
              ((equal record '("cleanup" "fixture" "PASS"))
               (when clean (fail "Duplicate cleanup receipt"))
               (setf clean t))
              ((and (= 7 (length record)) (member (first record) '("sample" "setup" "cleanup")
                                                  :test #'string=))
               (destructuring-bind (kind phase iteration seconds allocated launches result-bytes) record
                 (let ((value (obj "phase" phase
                                   "iteration" (parse-integer iteration)
                                   "seconds" (number-from seconds)
                                   "bytes_consed" (parse-integer allocated)
                                   "client_launches" (parse-integer launches)
                                   "result_bytes" (if (string= result-bytes "-")
                                                      :null (parse-integer result-bytes)))))
                   (when (some (lambda (key) (minusp (jref value key)))
                               '("seconds" "bytes_consed" "client_launches"))
                     (fail "Invalid benchmark measurement"))
                   (if (string= kind "sample") (push value samples) (push value timings)))))
              (t (fail "Unknown benchmark record")))))
    (setf metadata (nreverse metadata) samples (nreverse samples) timings (nreverse timings))
    (flet ((meta (key) (cdr (assoc key metadata :test #'string=))))
      (unless (and clean (every (lambda (key) (plusp (length (or (meta key) ""))))
                                '("sbcl" "asdf" "tmux" "control" "clock" "clock-units-per-second")))
        (fail "Missing runtime or cleanup evidence"))
      (unless (member (meta "control") '("available" "unsupported-before-3.7" "unsupported-before-3.8")
                      :test #'string=)
        (fail "Unknown control qualification"))
      (let* ((control (string= "available" (meta "control")))
             (phases (append '("subprocess" "snapshot")
                             (and control '("control-serial" "control-queued"))))
             (expected-timings (cons "fixture" (and control '("control-open" "control-close")))))
        (validate-samples samples phases count)
        (unless (and (= (length timings) (length expected-timings))
                     (null (set-difference (mapcar (lambda (timing) (jref timing "phase")) timings)
                                           expected-timings :test #'string=))
                     (null (set-difference expected-timings
                                           (mapcar (lambda (timing) (jref timing "phase")) timings)
                                           :test #'string=)))
          (fail "Missing, duplicate or unexpected setup/cleanup measurements"))
        (dolist (sample samples)
          (let ((phase (jref sample "phase")))
            (unless (plusp (jref sample "seconds")) (fail "Sample is below clock resolution"))
            (cond ((string= phase "snapshot")
                   (unless (eq :null (jref sample "result_bytes"))
                     (fail "Snapshot does not expose application reply bytes")))
                  ((not (eql (jref sample "result_bytes") (* commands 257)))
                   (fail "Read lanes did not return the same workload")))
            (when (and (string= phase "subprocess") (/= (jref sample "client_launches") commands))
              (fail "Subprocess launch counter does not match the workload"))
            (when (and (uiop:string-prefix-p "control-" phase)
                       (/= 0 (jref sample "client_launches")))
              (fail "Persistent control unexpectedly launched a client"))))
        (values (cons :object (mapcar (lambda (pair) (cons (car pair) (cdr pair))) metadata))
                samples timings)))))

;;; Host resources and source identity

(sb-alien:define-alien-routine ("flock" %flock) sb-alien:int
  (descriptor sb-alien:int) (operation sb-alien:int))
(sb-alien:define-alien-routine ("statvfs" %statvfs) sb-alien:int
  (path sb-alien:c-string) (buffer (* sb-alien:unsigned-long)))
(sb-alien:define-alien-routine ("sysconf" %sysconf) sb-alien:long (name sb-alien:int))

(defun free-disk-bytes (directory)
  "Free bytes for unprivileged users on the filesystem holding DIRECTORY (statvfs f_bavail * f_frsize)."
  (sb-alien:with-alien ((buffer (array sb-alien:unsigned-long 32)))
    (unless (zerop (%statvfs (uiop:native-namestring directory) (sb-alien:cast buffer (* sb-alien:unsigned-long))))
      (fail "statvfs failed for ~A" directory))
    (* (sb-alien:deref buffer 1) (sb-alien:deref buffer 4))))

(defun resources ()
  (let ((meminfo (read-text "/proc/meminfo"))
        (ticks (remove "" (cdr (uiop:split-string
                                (first (uiop:split-string (read-text "/proc/stat")
                                                          :separator '(#\Newline)))
                                :separator '(#\Space)))
                       :test #'string=)))
    (obj "load_average" (coerce (mapcar #'number-from
                                        (subseq (uiop:split-string (read-text "/proc/loadavg")
                                                                   :separator '(#\Space))
                                                0 3))
                                'vector)
         "cpu_count" (%sysconf 84)
         "cpu_ticks" (coerce (mapcar #'parse-integer (subseq ticks 0 8)) 'vector)
         "available_memory_kib" (parse-integer
                                 (aref (nth-value 1 (cl-ppcre:scan-to-strings
                                                     "(?m)^MemAvailable:\\s+(\\d+)" meminfo))
                                       0))
         "free_disk_bytes" (free-disk-bytes (uiop:getcwd)))))

(defun source-identity (root)
  "Bind a checkout or extracted archive to its actual runtime source bytes."
  (let* ((checkout (and (zerop (run '("git" "rev-parse" "--show-toplevel") :directory root
                                    :error-output nil :check nil))
                        (equal (truename (uiop:ensure-directory-pathname
                                          (git root "rev-parse" "--show-toplevel")))
                               (truename root))))
         (names (append '("libtmux.asd" "scripts/benchmark/benchmark.lisp" "tools/benchmark.lisp"
                          "scripts/test-processes/test-processes.lisp")
                        (mapcar (lambda (path) (enough-namestring path root))
                                (sort (directory (merge-pathnames "src/*.lisp" root)) #'string<
                                      :key #'namestring)))))
    (list (cons "source_kind" (if checkout "checkout" "archive-or-unversioned"))
          (cons "source_revision" (if checkout (git root "rev-parse" "HEAD") :null))
          (cons "source_dirty" (if checkout
                                   (if (plusp (length (git root "status" "--porcelain"
                                                           "--untracked-files=normal")))
                                       :true :false)
                                   :null))
          (cons "source_sha256" (cons :object (mapcar (lambda (name)
                                                        (cons name (sha256-file (merge-pathnames name root))))
                                                      names))))))

(defun option (arguments name default low high)
  (let ((text (second (member name arguments :test #'string=))))
    (if text
        (let ((value (parse-integer text :junk-allowed t)))
          (unless (and value (<= low value high))
            (fail "~A must be ~D..~D" name low high))
          value)
        default)))

(defun phase-summary (samples phase)
  (cons :object (loop for key in '("seconds" "bytes_consed" "client_launches")
                      collect (cons key (summarize
                                         (loop for sample in samples
                                               when (string= phase (jref sample "phase"))
                                                 collect (jref sample key)))))))

(defun new-directory (root output-argument)
  (if output-argument
      (let ((path (uiop:ensure-directory-pathname (merge-pathnames output-argument (uiop:getcwd)))))
        (when (probe-file path) (fail "~A already exists" path))
        (ensure-directories-exist path)
        path)
      (let ((base (merge-pathnames "dist/benchmarks/" root)))
        (ensure-directories-exist base)
        (uiop:ensure-directory-pathname
         (sb-posix:mkdtemp
          (uiop:native-namestring
           (merge-pathnames
            (multiple-value-bind (second minute hour day month year)
                (decode-universal-time (get-universal-time) 0)
              (format nil "run-~4,'0D~2,'0D~2,'0DT~2,'0D~2,'0D~2,'0D-XXXXXX"
                      year month day hour minute second))
            base)))))))

(defun measure (root directory program samples commands panes report)
  "Run the workload under the supervisor and fill REPORT, a function of KEY and VALUE."
  (let* ((records (merge-pathnames "records.tsv" directory))
         (code (run (list "sbcl" "--script"
                          (uiop:native-namestring
                           (merge-pathnames "scripts/test-processes/test-processes.lisp" root))
                          "sbcl" "--script"
                          (uiop:native-namestring (merge-pathnames "tools/benchmark.lisp" root))
                          (uiop:native-namestring program)
                          (princ-to-string samples) (princ-to-string commands)
                          (princ-to-string panes) (uiop:native-namestring records))
                    :directory root
                    :environment (clean-test-environment)
                    :output (merge-pathnames "run.log" directory)
                    :error-output :output :check nil)))
    (funcall report "exit_code" code)
    (unless (eql 0 code)
      (fail "Native benchmark or owned-residue check failed; inspect run.log"))
    (multiple-value-bind (metadata observed timings) (read-records records samples commands)
      (funcall report "runtime" metadata)
      (funcall report "samples" (coerce observed 'vector))
      (funcall report "setup_cleanup" (coerce timings 'vector))
      (let ((phases (loop for phase in (sort (remove-duplicates (mapcar (lambda (s) (jref s "phase")) observed)
                                                                :test #'string=)
                                             #'string<)
                          collect (cons phase (phase-summary observed phase)))))
        (funcall report "phases" (cons :object phases))
        (funcall report "comparisons"
                 (cons :object
                       (loop for lane in '("control-serial" "control-queued")
                             when (assoc lane phases :test #'string=)
                               collect (cons lane (compare
                                                   (jref (cdr (assoc "subprocess" phases :test #'string=)) "seconds")
                                                   (jref (cdr (assoc lane phases :test #'string=)) "seconds")))))))
      (funcall report "status" "PASS")
      (funcall report "owned_residue" "NONE"))))

(defun main ()
  (let* ((arguments (rest sb-ext:*posix-argv*))
         (root (directory-above *load-truename* 2))
         (samples (option arguments "--samples" 20 6 200))
         (commands (option arguments "--commands" 8 1 32))
         (panes (option arguments "--panes" 4 1 16))
         (program (or (find-program (or (second (member "--program" arguments :test #'string=))
                                        (nonblank-env "LIBTMUX_TEST_TMUX") "tmux"))
                      (fail "Select a native tmux binary with --program")))
         (lock-path (merge-pathnames "libtmux-lisp/benchmark.lock"
                                     (uiop:ensure-directory-pathname
                                      (or (uiop:getenv "XDG_CACHE_HOME")
                                          (merge-pathnames ".cache/" (user-homedir-pathname))))))
         (lock (progn (ensure-directories-exist lock-path)
                      (sb-posix:open (uiop:native-namestring lock-path)
                                     (logior sb-posix:o-wronly sb-posix:o-creat sb-posix:o-append) #o644))))
    (unless (zerop (%flock lock 6))
      (fail "Another libtmux-lisp benchmark is running"))
    (let* ((directory (new-directory root (second (member "--output" arguments :test #'string=))))
           (started (monotonic-seconds))
           (before (resources))
           (entries (append (list (cons "status" "FAIL")
                                  (cons "workload" (obj "samples" samples "commands" commands "panes" panes
                                                        "payload_bytes" 256 "warmup_rounds" 3)))
                            (source-identity root)
                            (list (cons "tmux_sha256" (sha256-file program))
                                  (cons "host" (obj "system" (software-type) "kernel" (software-version)
                                                    "architecture" "x86_64"))
                                  (cons "before" before)
                                  (cons "statistics"
                                        (obj "bootstrap_resamples" 2000 "seed" 0
                                             "interval" "percentile 95% median"
                                             "tail" "nearest rank p95, at least 20 observations"
                                             "latency_unit" "one complete phase batch"))))))
      (flet ((put (key value)
               (let ((cell (assoc key entries :test #'string=)))
                 (if cell (setf (cdr cell) value) (setf entries (append entries (list (cons key value))))))))
        (handler-case (measure root directory program samples commands panes #'put)
          (script-failure (condition) (put "error" (princ-to-string condition))))
        (let* ((after (resources))
               (ticks (map 'list #'- (jref after "cpu_ticks") (jref before "cpu_ticks"))))
          (put "after" after)
          (put "elapsed_seconds" (/ (round (* 1000 (- (monotonic-seconds) started))) 1000d0))
          (put "host_busy_percent"
               (if (plusp (reduce #'+ ticks))
                   (/ (round (* 10000 (- 1 (/ (+ (fourth ticks) (fifth ticks)) (reduce #'+ ticks))))) 100d0)
                   :null))
          (json-write-file (merge-pathnames "report.json" directory) (cons :object entries))))
      (sb-posix:close lock)
      (let ((status (cdr (assoc "status" entries :test #'string=))))
        (format t "~A~%" (json-string (obj "status" status "evidence" (car (last (pathname-directory directory)))
                                           "elapsed_seconds" (cdr (assoc "elapsed_seconds" entries :test #'string=)))
                                      :indent nil))
        (if (string= status "PASS") 0 1)))))

(main-when-script #'main)
