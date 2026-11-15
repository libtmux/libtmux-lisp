;;; The workspace command line:
;;;
;;;   sbcl --script tools/workspace-cli.lisp validate|plan|apply|inspect FILE ...
;;;
;;; Run it from any directory; paths in the arguments are relative to that one.

(load (merge-pathnames "load.lisp" *load-truename*))
(asdf:load-system "libtmux/workspace/cli")
(uiop:quit (uiop:symbol-call :libtmux.workspace.cli :main))
