;;; Read a class docstring's capability directory the way the documentation
;;; site does, so a malformed directory fails here and not silently there.
;;;
;;; The site folds three or more bold-led paragraphs, each followed by a
;;; paragraph that holds only references, into a table of task groups. Text
;;; that misses the shape stays ordinary prose. This library of two functions
;;; is loaded by scripts/check-documentation-artifact; it has no entry point.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))
(unless (find-package "CL-PPCRE")
  (asdf:load-system "cl-ppcre"))

(defpackage #:libtmux.scripts.api-directory
  (:use #:cl)
  (:export #:fold #:references-only))

(in-package #:libtmux.scripts.api-directory)

(defparameter *minimum-rows* 3)

(defun references-only (text)
  "Return the references of a paragraph made of nothing else, or NIL."
  (let* ((references (mapcar (lambda (match) (string-trim "`" match))
                             (cl-ppcre:all-matches-as-strings "`[a-z][\\w.]*:[^\\s`]+`" text)))
         (rest (cl-ppcre:regex-replace-all
                "\\band\\b"
                (cl-ppcre:regex-replace-all "`[a-z][\\w.]*:[^\\s`]+`" text "")
                "")))
    (and references
         (zerop (length (cl-ppcre:regex-replace-all "[\\s,;.]" rest "")))
         references)))

(defun paragraphs (body)
  "Split BODY at blank lines into paragraphs with single-spaced words."
  (loop for block in (cl-ppcre:split "\\n\\n" body)
        for words = (remove "" (cl-ppcre:split "\\s+" block) :test #'string=)
        when words collect (format nil "~{~A~^ ~}" words)))

(defun fold (body)
  "Return two values: the folded directories and the bold-led titles left as prose.
Each directory is a run of at least three (TITLE REFERENCES) rows."
  (let ((blocks (coerce (paragraphs body) 'vector))
        (runs '()) (run '()) (strays '()) (index 0))
    (flet ((flush ()
             (if (>= (length run) *minimum-rows*)
                 (push (reverse run) runs)
                 (dolist (row (reverse run)) (push (first row) strays)))
             (setf run '()))
           (lead-title (block)
             (multiple-value-bind (match groups)
                 (cl-ppcre:scan-to-strings "^\\*\\*([^*]+?)\\*\\*\\s*(.*)$" block)
               (and match (string-right-trim ".:" (aref groups 0))))))
      (loop while (< index (length blocks))
            do (let* ((title (lead-title (aref blocks index)))
                      (references (and title (< (1+ index) (length blocks))
                                       (references-only (aref blocks (1+ index))))))
                 (cond (references (push (list title references) run)
                                   (incf index 2))
                       (t (flush)
                          (when title (push title strays))
                          (incf index)))))
      (flush))
    (values (nreverse runs) (nreverse strays))))
