;;; Provision one pinned tmux release on Linux x86-64; never install packages.
;;;
;;;   sbcl --script scripts/provision-tmux/provision-tmux.lisp \
;;;       --manifest tools/tmux-sources.json --version 3.8 \
;;;       --output-dir build/tmux --cache-dir .cache/tmux \
;;;       [--jobs 1|2] [--print-cache-key] [--reuse]
;;;
;;; The manifest pins each release to a tmux commit and the SHA-256 of its
;;; GitHub source archive. The script downloads that archive with curl, builds
;;; it with the host toolchain (byacc, autoconf, automake, libevent and
;;; ncurses, which the build-tmux action installs) and records provenance under
;;; OUTPUT-DIR. --print-cache-key prints `key=VALUE` without downloading or
;;; building. --reuse validates and keeps a matching earlier build. The
;;; .github/actions/build-tmux action runs this script; tests and the options
;;; catalog use the same manifest. This port keeps its own build recipe, byacc
;;; included, because the shared libtmux/.github build-tmux action builds
;;; release archives with bison and does not read this manifest.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))

(defpackage #:libtmux.scripts.provision-tmux
  (:use #:cl #:libtmux.scripts)
  (:export #:manifest-cell #:elf-x86-64-p #:cache-key))

(in-package #:libtmux.scripts.provision-tmux)

(defparameter *needed* '("cc" "make" "autoconf" "automake" "aclocal" "autoreconf" "yacc" "pkg-config"))
(defparameter *packages* '("gcc" "libc6" "libevent-dev" "libncurses-dev" "autoconf" "automake"
                           "byacc" "make" "pkg-config"))
(defparameter *step-seconds* 300)
(defparameter *archive-limit* (* 64 1024 1024))

(defun hex-p (string length)
  (and (stringp string) (= length (length string))
       (every (lambda (c) (or (digit-char-p c) (char<= #\a c #\f))) string)))

(defun version-p (string)
  "True for MAJOR.MINOR with an optional trailing lowercase letter, such as 3.3a."
  (let* ((dot (position #\. string))
         (end (length string))
         (tail (and dot (> end (1+ dot)) (lower-case-p (char string (1- end))))))
    (and dot (plusp dot)
         (every #'digit-char-p (subseq string 0 dot))
         (let ((minor (subseq string (1+ dot) (if tail (1- end) end))))
           (and (plusp (length minor)) (every #'digit-char-p minor))))))

(defun manifest-cell (manifest version)
  "Return VERSION's validated manifest cell, or signal a script failure."
  (let ((matches (remove-if-not (lambda (cell) (equal version (jref cell "tmux")))
                                (coerce (jref manifest "cells") 'list))))
    (unless (= 1 (length matches)) (fail "Select one exact version from the manifest"))
    (let ((cell (first matches)))
      (unless (version-p version) (fail "Invalid version key"))
      (unless (and (hex-p (jref cell "commit") 40)
                   (hex-p (let ((entry (jhas cell "archive_sha256"))) (if entry (cdr entry) "")) 64))
        (fail "The manifest must pin a full commit and archive SHA256"))
      (unless (equal (format nil "https://codeload.github.com/tmux/tmux/tar.gz/~A" (jref cell "commit"))
                     (let ((entry (jhas cell "archive_url"))) (and entry (cdr entry))))
        (fail "The archive URL must identify the exact pinned tmux commit"))
      cell)))

(defun elf-x86-64-p (path)
  "True when the file at PATH starts like a 64-bit little-endian x86-64 ELF executable."
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((header (make-array 20 :element-type '(unsigned-byte 8))))
      (and (= 20 (read-sequence header stream))
           (equalp #(127 69 76 70 2 1) (subseq header 0 6))
           (= 62 (+ (aref header 18) (* 256 (aref header 19))))))))

(defun binary-record (path version environment)
  (unless (elf-x86-64-p path) (fail "Artifact is not x86_64 ELF"))
  (let ((shown (string-trim '(#\Space #\Newline)
                            (nth-value 1 (run (list (uiop:native-namestring path) "-V")
                                              :environment environment :timeout 5)))))
    (unless (string= shown (concatenate 'string "tmux " version))
      (fail "Unexpected binary version: ~A" shown))
    (obj "path" (uiop:native-namestring path) "sha256" (sha256-file path) "version_output" shown)))

(defun os-release ()
  (cons :object
        (loop for line in (uiop:split-string (read-text "/etc/os-release") :separator '(#\Newline))
              for equals = (position #\= line)
              when (and equals (plusp equals))
                collect (cons (subseq line 0 equals) (string-trim "\"" (subseq line (1+ equals)))))))

(defun output-lines (argv)
  (remove "" (uiop:split-string (nth-value 1 (run argv)) :separator '(#\Newline)) :test #'string=))

(defun build-identity (manifest-path script cell environment)
  (obj "source" cell "manifest_sha256" (sha256-file manifest-path) "provisioner_sha256" (sha256-file script)
       "compiler" (first (output-lines '("cc" "--version")))
       "libraries" (obj "libevent" (string-trim '(#\Newline)
                                                (nth-value 1 (run '("pkg-config" "--modversion" "libevent"))))
                        "ncurses" (string-trim '(#\Newline)
                                               (nth-value 1 (run '("pkg-config" "--modversion" "ncurses")))))
       "packages" (coerce (sort (output-lines (list* "dpkg-query" "-W" "-f=${Package}=${Version}\\n" *packages*))
                                #'string<)
                          'vector)
       "environment" (cons :object (loop for name in '("CC" "CFLAGS" "LC_ALL" "CONFIG_SITE")
                                         collect (cons name (second (assoc name (mapcar (lambda (entry)
                                                                                       (uiop:split-string entry :separator '(#\=) :max 2))
                                                                                     environment)
                                                                       :test #'string=)))))
       "host" (obj "system" "Linux" "machine" "x86_64" "os_release" (os-release)
                   "image_os" (or (uiop:getenv "ImageOS") :null)
                   "image_version" (or (uiop:getenv "ImageVersion") :null))))

(defun cache-key (version identity)
  (with-temporary-directory (directory "libtmux-provision-key")
    (let ((path (write-text (merge-pathnames "identity.json" directory)
                            (json-string identity :indent nil :sort-keys t))))
      (format nil "tmux-~A-~A" version (sha256-file path)))))

(defun build-step (argv directory environment log records)
  "Run one build step into LOG; record it and fail when it times out or exits nonzero."
  (let* ((started (monotonic-seconds))
         (name (first argv))
         (code (run argv :directory directory :environment environment :output log :error-output :output
                         :timeout *step-seconds* :check nil)))
    (push (obj "argv" (coerce argv 'vector) "cwd" (uiop:native-namestring directory)
               "seconds" (/ (round (* 1000 (- (monotonic-seconds) started))) 1000d0)
               "exit" (or code :null) "log" (uiop:native-namestring log)
               "log_sha256" (sha256-file log))
          (cdr records))
    (unless (eql 0 code) (fail "~A failed; inspect ~A" name (file-namestring log)))))

(defun download (url destination sha256)
  (run (list "curl" "--fail" "--silent" "--show-error" "--location" "--proto" "=https"
             "--max-time" "120" "--max-filesize" (princ-to-string *archive-limit*)
             "--output" (uiop:native-namestring destination) url))
  (unless (equal sha256 (sha256-file destination)) (fail "Downloaded archive SHA256 mismatch")))

(defun extract (archive destination commit)
  (let ((root (format nil "tmux-~A" commit)))
    (dolist (name (output-lines (list "tar" "-tzf" (uiop:native-namestring archive))))
      (let ((parts (uiop:split-string name :separator '(#\/))))
        (unless (and (string= root (first parts)) (not (member ".." parts :test #'string=)))
          (fail "Archive root differs from pinned commit"))))
    (run (list "tar" "-xzf" (uiop:native-namestring archive) "-C" (uiop:native-namestring destination)
               "--no-same-owner" "--no-same-permissions"))
    (merge-pathnames (format nil "~A/" root) destination)))

(defun option (arguments name) (second (member name arguments :test #'string=)))

(defun main ()
  (let* ((arguments (rest sb-ext:*posix-argv*))
         (manifest-path (merge-pathnames (or (option arguments "--manifest") (fail "--manifest is required"))
                                         (uiop:getcwd)))
         (version (or (option arguments "--version") (fail "--version is required")))
         (output (uiop:ensure-directory-pathname
                  (merge-pathnames (or (option arguments "--output-dir") (fail "--output-dir is required"))
                                   (uiop:getcwd))))
         (cache (uiop:ensure-directory-pathname
                 (merge-pathnames (or (option arguments "--cache-dir") (fail "--cache-dir is required"))
                                  (uiop:getcwd))))
         (jobs (let ((text (or (option arguments "--jobs") "2")))
                 (unless (member text '("1" "2") :test #'string=) (fail "--jobs must be 1 or 2"))
                 text))
         (print-key (member "--print-cache-key" arguments :test #'string=))
         (reuse (member "--reuse" arguments :test #'string=))
         (script *load-truename*)
         (started (monotonic-seconds))
         (cell (manifest-cell (json-read-file manifest-path) version))
         (commit (jref cell "commit"))
         (logs (merge-pathnames (format nil "logs/~A/" version) output))
         (destination (merge-pathnames (format nil "bin/~A/tmux" version) output))
         (provenance (merge-pathnames (format nil "provenance/~A.json" version) output))
         (record (list (cons "tmux" version) (cons "purpose" (jref cell "purpose"))
                       (cons "scope" "provisioning-only") (cons "native_runtime_evidence" "UNVERIFIED")
                       (cons "manifest_sha256" (sha256-file manifest-path))
                       (cons "provisioner_sha256" (sha256-file script))
                       (cons "source" cell) (cons "commands" (list :commands)) (cons "jobs" (parse-integer jobs))))
         (records (cdr (assoc "commands" record :test #'string=)))
         (build nil))
    (dolist (directory (list logs (merge-pathnames "provenance/" output)
                             (merge-pathnames "archives/" cache) (merge-pathnames "builds/" cache)))
      (ensure-directories-exist directory))
    (flet ((put (key value)
             (let ((entry (assoc key record :test #'string=)))
               (if entry (setf (cdr entry) value) (setf record (append record (list (cons key value))))))))
      (handler-case
          (block provisioning
            (let ((missing (remove-if #'find-program *needed*)))
              (when missing (fail "Missing build prerequisites: ~{~A~^, ~}" missing)))
            (let* ((environment (environment-with (sb-ext:posix-environ) "CC" "cc" "CFLAGS" "-O2" "LC_ALL" "C"
                                                  "CONFIG_SITE" "/dev/null" "CPPFLAGS" nil "LDFLAGS" nil
                                                  "LIBS" nil "MAKEFLAGS" nil "MFLAGS" nil))
                   (identity (build-identity manifest-path script cell environment))
                   (key (cache-key version identity)))
              (put "build_identity" identity)
              (put "cache_key" key)
              (put "reused" :false)
              (when print-key
                (format t "key=~A~%" key)
                (return-from main 0))
              (when (and reuse (probe-file provenance))
                (handler-case
                    (let ((previous (json-read-file provenance)))
                      (unless (and (<= (with-open-file (stream provenance) (file-length stream)) 1048576)
                                   (equal "PASS" (jref previous "provisioning"))
                                   (json-equal identity (jref previous "build_identity")))
                        (fail "Cached build identity does not match"))
                      (unless (equal (sha256-file destination) (jref previous "binary" "sha256"))
                        (fail "Cached binary SHA256 mismatch"))
                      (put "binary" (binary-record destination version environment))
                      (put "provisioning" "PASS")
                      (put "reused" :true)
                      (return-from provisioning))
                  (error (condition) (put "cache_rejection" (princ-to-string condition)))))
              (let ((archive (merge-pathnames (format nil "archives/~A.tar.gz" commit) cache)))
                (unless (probe-file archive)
                  (let ((temporary (merge-pathnames (format nil "archives/~A.download" commit) cache)))
                    (unwind-protect
                         (progn (download (jref cell "archive_url") temporary (jref cell "archive_sha256"))
                                (rename-file temporary archive))
                      (when (probe-file temporary) (delete-file temporary)))))
                (unless (equal (sha256-file archive) (jref cell "archive_sha256"))
                  (fail "Cached archive SHA256 mismatch"))
                (put "archive_verified" :true)
                (setf build (uiop:ensure-directory-pathname
                             (sb-posix:mkdtemp (uiop:native-namestring
                                                (merge-pathnames (format nil "builds/tmux-~A-XXXXXX" version)
                                                                 cache)))))
                (let ((source (extract archive build commit)))
                  (loop for (stage argv) in (list (list "autogen" '("sh" "autogen.sh"))
                                                  (list "configure" '("./configure" "--prefix=/usr/local" "--sysconfdir=/etc"))
                                                  (list "make" (list "make" (format nil "-j~A" jobs))))
                        do (format *error-output* "~A: ~A~%" version stage)
                           (finish-output *error-output*)
                           (build-step argv source environment (merge-pathnames (format nil "~A.log" stage) logs) records))
                  (ensure-directories-exist destination)
                  (uiop:copy-file (merge-pathnames "tmux" source) destination)
                  (sb-posix:chmod (uiop:native-namestring destination) #o755)
                  (put "binary" (binary-record destination version environment))
                  (put "provisioning" "PASS")))))
        (error (condition)
          (put "provisioning" "FAIL")
          (put "failure" (princ-to-string condition))
          (when print-key (format *error-output* "~A~%" condition))))
      (when build
        (let ((source (merge-pathnames (format nil "tmux-~A/" commit) build)))
          (dolist (name '("config.log" "config.status" "config.h" "Makefile"))
            (when (probe-file (merge-pathnames name source))
              (uiop:copy-file (merge-pathnames name source) (merge-pathnames name logs)))))
        (uiop:delete-directory-tree build :validate t :if-does-not-exist :ignore)
        (put "build_directory_removed" (if (probe-file build) :false :true)))
      (unless print-key
        (put "whole_seconds" (/ (round (* 1000 (- (monotonic-seconds) started))) 1000d0))
        (json-write-file provenance (cons :object (loop for (key . value) in record
                                                        collect (cons key (if (and (consp value) (eq :commands (car value)))
                                                                              (coerce (reverse (cdr value)) 'vector)
                                                                              value)))))
        (format t "~A~%" (json-string (obj "provisioning" (cdr (assoc "provisioning" record :test #'string=))
                                           "reused" (cdr (assoc "reused" record :test #'string=))
                                           "native_runtime_evidence" "UNVERIFIED"
                                           "binary" (or (cdr (assoc "binary" record :test #'string=)) :null)
                                           "provenance" (uiop:native-namestring provenance)
                                           "failure" (or (cdr (assoc "failure" record :test #'string=)) :null))
                                      :indent nil)))
      (if (equal "PASS" (cdr (assoc "provisioning" record :test #'string=))) 0 1))))

(main-when-script #'main)
