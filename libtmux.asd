(defsystem "libtmux"
  :description "Native Common Lisp tmux library"
  :version "0.1.0"
  :license "MIT"
  :homepage "https://github.com/libtmux/libtmux-lisp"
  :source-control (:git "https://github.com/libtmux/libtmux-lisp.git")
  :depends-on ("uiop")
  :in-order-to ((test-op (test-op "libtmux/tests")
                         (test-op "libtmux/tests/query")))
  :serial t
  :components ((:file "src/package"
                      :description "Public and internal packages; connection, observation and operation contracts.")
               (:file "src/conditions"
                      :description "Typed failure conditions and retained diagnostic readers.")
               (:file "src/transport"
                      :description "Owned command outcomes, cancellation tokens and transport validation.")
               #+sbcl (:file "src/backend-sbcl"
                      :description "SBCL/Linux synchronization and native operating-system capability checks.")
               #+sbcl (:file "src/process-sbcl"
                      :description "Bounded subprocess lifecycle, nonblocking pipe service and cleanup ownership.")
               (:file "src/client"
                      :description "Connection scopes, single-operation leases and explicit raw tmux commands.")
               (:file "src/command-policy"
                      :description "Required built-in command meanings and daemon alias validation.")
               (:file "src/registry"
                      :description "Typed captured fields, relationships and wire scalar validation.")
               (:file "src/records"
                      :description "Reversible bounded tmux row framing and strict text decoding.")
               (:file "src/model"
                      :description "Captured CLOS observations, local readers, identity and owned projections.")
               (:file "src/graph"
                      :description "Physical-entity normalization, explicit window links and graph consistency.")
               #+sbcl (:file "src/witness-sbcl"
                      :description "Server generation authority using socket and Linux process identities.")
               (:file "src/capture"
                      :description "Explicit bounded acquisition and replacement observations.")
               (:file "src/command-encoding"
                      :description "Literal, format, argv and shell-source boundaries for tmux commands.")
               (:file "src/configuration-codec"
                      :description "Private bounded decoding of tmux values, guarded prefixes and environment frames.")
               (:file "src/options-catalog"
                      :description "Generated exact-version tmux option and hook schema facts.")
               (:file "src/configuration-registry"
                      :description "Native option discovery, scope authority and typed value/key normalization.")
               (:file "src/configuration-options"
                      :description "Private typed decoding of known option and hook records across exact tmux schemas.")
               (:file "src/dispatch"
                      :description "Target guards, dispatch evidence and independent observation outcomes.")
               (:file "src/configuration-operations"
                      :description "Typed option, hook and environment mutations over live versioned schemas.")
               (:file "src/operations"
                      :description "Rename, select and terminal capture operations with explicit clients.")
               (:file "src/creation"
                      :description "Detached session/window/pane creation from argv or explicit shell source.")
               (:file "src/process-operations"
                      :description "Explicit pane respawn and daemon-owned shell pipe configuration.")
               (:file "src/terminal-operations"
                      :description "Literal text, key input, prefix, copy mode and history operations.")
               (:file "src/geometry"
                      :description "Bounded pane/window dimensions and tmux layout operations.")
               (:file "src/selection"
                      :description "Contextual next, previous and last window/pane selection.")
               (:file "src/placement"
                      :description "Physical pane placement and contextual window-link operations.")
               (:file "src/buffers"
                      :description "Owned binary buffers, file transfer and explicit pane paste operations.")
               (:file "src/termination"
                      :description "Exact entity deletion and separately proven explicit server termination.")))

(defsystem "libtmux/tests"
  :description "Local semantic tests for libtmux"
  :depends-on ("libtmux" "fiveam")
  :serial t
  :components ((:file "tests/package")
               (:file "tests/resources")
               (:file "tests/records")
               (:file "tests/configuration-codec")
               (:file "tests/configuration-registry")
               (:file "tests/configuration-options")
               (:file "tests/model"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :libtmux.tests :run-suite :unit)
               (error "libtmux unit tests failed"))))

(defsystem "libtmux/query"
  :description "Validated native queries over captured observations"
  :depends-on ("libtmux")
  :in-order-to ((test-op (test-op "libtmux/tests/query")))
  :serial t
  :components ((:file "src/query"
                      :description "Owned expressions, relation traversal, eager query sets and strict cardinality.")))

(defsystem "libtmux/regex"
  :description "Optional CL-PPCRE operators for native captured queries"
  :depends-on ("libtmux/query" "cl-ppcre")
  :in-order-to ((test-op (test-op "libtmux/tests/regex")))
  :serial t
  :components ((:file "src/regex"
                      :description "Validated CL-PPCRE search and full-match query operators.")))

(defsystem "libtmux/json"
  :description "Optional bounded JSON interchange for native query filters"
  :depends-on ("libtmux/query" "com.inuoe.jzon")
  :in-order-to ((test-op (test-op "libtmux/tests/json")))
  :serial t
  :components ((:file "src/json"
                      :description "Closed versioned filter documents with bounded event decoding.")))

(defsystem "libtmux/workspace"
  :description "Owned workspace descriptions, pure plans and explicit application"
  :depends-on ("libtmux" "com.inuoe.jzon")
  :in-order-to ((test-op (test-op "libtmux/tests/workspace")))
  :serial t
  :components ((:file "src/workspace"
                      :description "Closed workspace data, bounded JSON, pure topology plans and explicit apply.")))

(defsystem "libtmux/workspace/cli"
  :description "Explicit-endpoint workspace command-line interface"
  :depends-on ("libtmux/workspace")
  :serial t
  :components ((:file "src/workspace-cli"
                      :description "Validate, plan and apply workspace documents with bounded JSON summaries.")))

(defsystem "libtmux/tests/query"
  :description "Local native-query semantic tests"
  :depends-on ("libtmux/tests" "libtmux/query")
  :serial t
  :components ((:file "tests/query"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :libtmux.tests :run-suite :query)
               (error "libtmux query tests failed"))))

(defsystem "libtmux/tests/regex"
  :description "Optional CL-PPCRE query semantic tests"
  :depends-on ("libtmux/tests" "libtmux/regex")
  :serial t
  :components ((:file "tests/regex"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :libtmux.tests :run-suite :regex)
               (error "libtmux regex tests failed"))))

(defsystem "libtmux/tests/json"
  :description "Optional bounded query-interchange semantic tests"
  :depends-on ("libtmux/tests" "libtmux/regex" "libtmux/json")
  :serial t
  :components ((:file "tests/json"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :libtmux.tests :run-suite :json)
               (error "libtmux JSON tests failed"))))

(defsystem "libtmux/tests/workspace"
  :description "Local workspace validation and planning tests"
  :depends-on ("libtmux/tests" "libtmux/workspace/cli")
  :serial t
  :components ((:file "tests/workspace")
               (:file "tests/workspace-cli"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :libtmux.tests :run-suite :workspace)
               (error "libtmux workspace tests failed"))))

(defsystem "libtmux/tests/integration"
  :description "Owned tmux fixtures and external-operation tests"
  :depends-on ("libtmux/tests" "libtmux/workspace/cli")
  :serial t
  :components ((:file "tests/fixture")
               (:file "tests/process")
               (:file "tests/capture")
               (:file "tests/operations")
               (:file "tests/termination")
               (:file "tests/creation")
               (:file "tests/geometry")
               (:file "tests/placement")
               (:file "tests/buffers")
               (:file "tests/pane-processes")
               (:file "tests/workspace-integration"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :libtmux.tests :run-suite :integration)
               (error "libtmux integration tests failed"))))
