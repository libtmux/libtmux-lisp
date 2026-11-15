;;; Load the pinned ASDF, the project's Qlot environment and libtmux.asd.
;;;
;;; `sbcl --script` skips the system and user init files, so every Lisp tool and
;;; example starts by loading this file:
;;;
;;;   (load (merge-pathnames "../tools/load.lisp" *load-truename*))
;;;
;;; Afterwards `(asdf:load-system "libtmux")` works from any directory.
;;;
;;; ASDF: the asdf.lisp that mise puts on PATH, compiled once into .cache/ at
;;; the project root; SBCL's bundled ASDF when mise is not in use.
;;; Qlot: .qlot/setup.lisp in the project root, or the file named by
;;; LIBTMUX_QLOT_SETUP. A tree without either runs on ASDF and UIOP alone.

(let* ((root (merge-pathnames "../" (make-pathname :name nil :type nil
                                                   :defaults *load-truename*)))
       (path (or (sb-ext:posix-getenv "PATH") ""))
       (asdf (loop with start = 0
                   for end = (or (position #\: path :start start) (length path))
                   for directory = (subseq path start end)
                   for candidate = (and (plusp (length directory))
                                        (probe-file (concatenate 'string directory "/asdf.lisp")))
                   when candidate return candidate
                   until (>= end (length path))
                   do (setf start (1+ end)))))
  (unless (find-package "ASDF")
    (if asdf
        (let ((fasl (merge-pathnames
                     (format nil ".cache/asdf-~A-~D.fasl"
                             (lisp-implementation-version) (file-write-date asdf))
                     root)))
          (unless (probe-file fasl)
            (ensure-directories-exist fasl)
            (let ((temporary (make-pathname :type "tmp" :defaults fasl))
                  (*standard-output* (make-broadcast-stream)))
              (handler-bind ((warning #'muffle-warning))
                (compile-file asdf :output-file temporary))
              (rename-file temporary fasl)))
          (load fasl))
        (require :asdf)))
  (let ((qlot (or (sb-ext:posix-getenv "LIBTMUX_QLOT_SETUP")
                  (probe-file (merge-pathnames ".qlot/setup.lisp" root)))))
    (when (and qlot (probe-file qlot)) (load qlot)))
  (funcall (intern "LOAD-ASD" "ASDF")
           (truename (merge-pathnames "libtmux.asd" root))))
