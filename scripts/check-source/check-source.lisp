;;; Check tracked and unignored source text for trailing whitespace, a missing
;;; final newline, and shell or Python script files, without network, installs
;;; or builds.
;;;
;;;   sbcl --script scripts/check-source/check-source.lisp
;;;
;;; Run by `mise run check`. Checks .lisp, .asd, .md, .toml and .yml files for
;;; whitespace, and every file for the second-language rule in
;;; .github/SCRIPTS.md: no .py or .sh file and no shell or Python shebang.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))

(defpackage #:libtmux.scripts.check-source
  (:use #:cl #:libtmux.scripts)
  (:export #:check-text #:check-language #:check-tree))

(in-package #:libtmux.scripts.check-source)

(defparameter *extensions* '("lisp" "asd" "md" "toml" "yml"))

(defun check-text (name text)
  "Return one message per problem in TEXT, the content of the file NAME."
  (let ((errors '()) (line-number 1) (start 0))
    (loop for end = (position #\Newline text :start start)
          while end
          do (when (and (> end start)
                        (member (char text (1- end))
                                '(#\Space #\Tab #\Return #\Page #\Vt)))
               (push (format nil "~A:~D: trailing whitespace" name line-number) errors))
             (setf start (1+ end))
             (incf line-number))
    (when (and (< start (length text)) (member (char text (1- (length text))) '(#\Space #\Tab)))
      (push (format nil "~A:~D: trailing whitespace" name line-number) errors))
    (when (and (plusp (length text)) (char/= #\Newline (char text (1- (length text)))))
      (push (format nil "~A: missing final newline" name) errors))
    (nreverse errors)))

(defun check-language (name text)
  "Return a message when NAME or its first line makes it a shell or Python script."
  (let* ((first-line (subseq text 0 (or (position #\Newline text) (length text))))
         (words (and (uiop:string-prefix-p "#!" first-line)
                     (remove "" (uiop:split-string (subseq first-line 2) :separator '(#\Space))
                             :test #'string=)))
         (interpreter (and words
                           (file-namestring (if (and (string= "env" (file-namestring (first words)))
                                                     (rest words))
                                                (second words)
                                                (first words))))))
    (when (or (member (pathname-type name) '("py" "sh") :test #'equal)
              (and interpreter
                   (or (member interpreter '("sh" "bash" "zsh" "dash") :test #'string=)
                       (uiop:string-prefix-p "python" interpreter))))
      (format nil "~A: shell and Python scripts are not allowed; write Common Lisp for sbcl --script"
              name))))

(defun source-names (root)
  (let ((listing (nth-value 1 (run (list "git" "ls-files" "-z" "--cached" "--others"
                                         "--exclude-standard")
                                   :directory root))))
    (remove "" (uiop:split-string listing :separator '(#\Null)) :test #'string=)))

(defun check-tree (root)
  "Return the problems in every source file git knows under ROOT."
  (loop for name in (source-names root)
        for path = (merge-pathnames name root)
        when (and (probe-file path)
                  (not (sb-posix:s-islnk
                        (sb-posix:stat-mode (sb-posix:lstat (uiop:native-namestring path))))))
          append (let ((text (if (or (member (pathname-type name) *extensions* :test #'equal)
                                     (member (pathname-type name) '("py" "sh") :test #'equal))
                                 (read-text path)
                                 "")))
                   (append (and (member (pathname-type name) *extensions* :test #'equal)
                                (check-text name text))
                           (let ((message (check-language name text))) (and message (list message)))))))

(defun main ()
  (let ((errors (check-tree (directory-above *load-truename* 2))))
    (format t "~:[Source checks passed~;~:*~{~A~^~%~}~]~%" errors)
    (when errors 1)))

(main-when-script #'main)
