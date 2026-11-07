(require :asdf)
(asdf:load-asd (merge-pathnames "../libtmux.asd" *load-truename*))
(asdf:load-system "libtmux")

(let* ((program (first (uiop:command-line-arguments)))
       (directory (sb-posix:mkdtemp "/tmp/libtmux-lisp-floor-XXXXXX"))
       (socket (concatenate 'string directory "/tmux.sock")))
  (unless program (error "Supply the exact tmux 3.3 executable"))
  (unwind-protect
       (progn
         (assert (equal "tmux 3.3"
                        (string-trim '(#\Newline #\Return)
                                     (uiop:run-program (list program "-V")
                                                       :force-shell nil :output :string))))
         (assert
          (handler-case
              (libtmux:with-client (client :program program :socket-path socket
                                          :config-file "/dev/null")
                (declare (ignore client)) nil)
            (libtmux:unsupported-tmux () t)))
         (assert (not (probe-file socket)))
         (format t "PASS: plain tmux 3.3 rejected without creating a server~%"))
    (uiop:delete-directory-tree (uiop:ensure-directory-pathname directory) :validate t)))
