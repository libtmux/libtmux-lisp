(defsystem "libtmux"
  :description "Native Common Lisp tmux library"
  :version "0.1.0"
  :license "MIT"
  :homepage "https://github.com/libtmux/libtmux-lisp"
  :source-control (:git "https://github.com/libtmux/libtmux-lisp.git")
  :depends-on ("uiop")
  :in-order-to ((test-op (test-op "libtmux/tests")))
  :serial t
  :components ((:file "src/package")
               (:file "src/conditions")
               (:file "src/transport")
               #+sbcl (:file "src/backend-sbcl")
               #+sbcl (:file "src/process-sbcl")
               (:file "src/client")
               (:file "src/command-policy")
               (:file "src/registry")
               (:file "src/records")
               (:file "src/model")
               (:file "src/graph")
               #+sbcl (:file "src/witness-sbcl")
               (:file "src/capture")))

(defsystem "libtmux/tests"
  :description "Local semantic tests for libtmux"
  :depends-on ("libtmux" "fiveam")
  :serial t
  :components ((:file "tests/package")
               (:file "tests/resources")
               (:file "tests/records")
               (:file "tests/model"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :libtmux.tests :run-suite :unit)
               (error "libtmux unit tests failed"))))

(defsystem "libtmux/tests/integration"
  :description "Owned tmux fixtures and external-operation tests"
  :depends-on ("libtmux/tests")
  :serial t
  :components ((:file "tests/fixture")
               (:file "tests/process")
               (:file "tests/capture"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :libtmux.tests :run-suite :integration)
               (error "libtmux integration tests failed"))))
