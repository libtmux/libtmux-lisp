(let ((asdf (sb-ext:posix-getenv "LIBTMUX_ASDF")))
  (if asdf (load asdf) (require :asdf)))

(let* ((root (uiop:pathname-directory-pathname
              (merge-pathnames "../" *load-truename*)))
       (qlot (or (uiop:getenv "LIBTMUX_QLOT_SETUP")
                 (namestring (merge-pathnames ".qlot/setup.lisp" root)))))
  (when (probe-file qlot) (load qlot))
  (asdf:load-asd (merge-pathnames "libtmux.asd" root))
  (asdf:load-system "libtmux/workspace/cli")
  (uiop:quit (uiop:symbol-call :libtmux.workspace.cli :main)))
