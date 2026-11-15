;;; Keep Markdown excerpts identical to the executable Lisp examples, and check
;;; local links, images and anchors in the README and the guides.
;;;
;;;   sbcl --script scripts/doc-examples/doc-examples.lisp [write]
;;;
;;; An excerpt is the block between `<!-- example:NAME -->` and `<!-- /example -->`;
;;; its source is the `;;; docs:NAME` ... `;;; docs:end` region of a file under
;;; examples/. Without `write` the script fails on a stale excerpt; with it, the
;;; script rewrites the excerpts. `mise run check` runs the first form and
;;; `mise run docs` the second.

(unless (find-package "LIBTMUX.SCRIPTS")
  (load (merge-pathnames "../../tools/load.lisp" *load-truename*))
  (load (merge-pathnames "../support/support.lisp" *load-truename*)))
(unless (find-package "CL-PPCRE")
  (asdf:load-system "cl-ppcre"))

(defpackage #:libtmux.scripts.doc-examples
  (:use #:cl #:libtmux.scripts)
  (:export #:read-snippets #:expected-text #:link-errors #:check-documents))

(in-package #:libtmux.scripts.doc-examples)

(defparameter *system-readmes*
  '("query/README.md" "regex/README.md" "json/README.md" "control/README.md"
    "workspace/README.md" "workspace/cli/README.md"))

(defun read-snippets (root)
  "Return a hash table from excerpt name to source, read from ROOT/examples/*.lisp."
  (let ((snippets (make-hash-table :test #'equal))
        (source (format nil "~{~A~^~%~}"
                        (mapcar #'read-text
                                (sort (directory (merge-pathnames "examples/*.lisp" root)
                                                 :resolve-symlinks nil)
                                      #'string< :key #'namestring)))))
    (cl-ppcre:do-register-groups (name body)
        ("(?ms)^;;; docs:(\\w+)\\n(.*?)^;;; docs:end$" source)
      (setf (gethash name snippets) body))
    snippets))

(defun expected-text (text snippets)
  "Return TEXT with every excerpt block replaced by its current example source."
  (cl-ppcre:regex-replace-all
   "(?s)<!-- example:(\\w+) -->.*?<!-- /example -->" text
   (lambda (match name)
     (declare (ignore match))
     (let ((body (gethash name snippets)))
       (unless body (fail "Unknown executable excerpt ~A" name))
       (format nil "<!-- example:~A -->~%```lisp~%~A~%```~%<!-- /example -->"
               name (string-right-trim '(#\Space #\Tab #\Newline #\Return) body))))
   :simple-calls t))

(defun anchors (body)
  (let ((anchors '()))
    (cl-ppcre:do-register-groups (heading) ("(?m)^#+ (.+)$" body)
      (push (substitute #\- #\Space
                        (cl-ppcre:regex-replace-all "[^\\w\\- ]" (string-downcase heading) ""))
            anchors))
    (cl-ppcre:do-register-groups (id) ("<a id=\"([^\"]+)\"" body)
      (push id anchors))
    anchors))

(defun resolve (location directory)
  (probe-file (uiop:merge-pathnames* (uiop:parse-unix-namestring location) directory)))

(defun link-errors (root path text)
  "Return a message for each broken local image, link or anchor in TEXT of PATH."
  (let ((name (enough-namestring path root))
        (directory (uiop:pathname-directory-pathname path))
        (errors '()))
    (cl-ppcre:do-register-groups (target) ("(?:src|srcset)=\"([^\"]+)\"" text)
      (when (and (not (search "://" target)) (not (uiop:string-prefix-p "data:" target))
                 (not (resolve target directory)))
        (push (format nil "Broken local image in ~A: ~A" name target) errors)))
    (cl-ppcre:do-register-groups (target) ("(?<!!)\\[[^\\]]+\\]\\(([^)]+)\\)" text)
      (unless (or (search "://" target) (uiop:string-prefix-p "mailto:" target))
        (let* ((hash (position #\# target))
               (location (subseq target 0 hash))
               (anchor (and hash (subseq target (1+ hash))))
               (destination (if (string= location "") path (resolve location directory))))
          (cond ((null destination)
                 (push (format nil "Broken local link in ~A: ~A" name target) errors))
                ((and anchor (equal "md" (pathname-type destination))
                      (not (member anchor (anchors (read-text destination)) :test #'string=)))
                 (push (format nil "Broken local anchor in ~A: ~A" name target) errors))))))
    (nreverse errors)))

(defun documents (root)
  (append (list (merge-pathnames "README.md" root))
          (mapcar (lambda (name) (merge-pathnames name root)) *system-readmes*)
          (sort (remove-if (lambda (path)
                             (member "_build" (pathname-directory (enough-namestring path
                                                                                    (merge-pathnames "docs/" root)))
                                     :test #'equal))
                           (directory (merge-pathnames "docs/**/*.md" root) :resolve-symlinks nil))
                #'string< :key #'namestring)))

(defun check-documents (root &key write)
  "Return the problems with every document under ROOT; with WRITE, refresh excerpts."
  (let ((snippets (read-snippets root)) (errors '()))
    (dolist (path (documents root))
      (let* ((text (read-text path))
             (expected (expected-text text snippets)))
        (unless (string= expected text)
          (if write
              (progn (write-text path expected) (setf text expected))
              (push (format nil "Stale example excerpt: ~A" (enough-namestring path root))
                    errors)))
        (dolist (message (link-errors root path text)) (push message errors))))
    (nreverse errors)))

(defun main ()
  (let* ((arguments (rest sb-ext:*posix-argv*))
         (write (equal arguments '("write")))
         (errors (check-documents (directory-above *load-truename* 2) :write write)))
    (cond (errors (format t "~{~A~^~%~}~%" errors) 1)
          (t (format t "Executable excerpts and local documentation links: PASS~%") 0))))

(main-when-script #'main)
