(in-package #:libtmux.tests)

(in-suite scripts)

(defparameter *tutorial-markdown*
  (format nil "Intro~%~%```lisp~%(one)~%```~%~%```console~%$ no~%```~%~%```lisp~%(two)~%```~%~%```lisp~%(terminate-owned-server *socket-path*)~%```~%~%```lisp~%(tm:stop-daemon *daemon*)~%```~%~%```lisp~%(uiop:quit)~%```~%"))

(test tutorial-runs-every-lisp-block-in-order-and-ends-by-stopping-its-daemon
  (let* ((forms (libtmux.scripts.examples:tutorial-forms *tutorial-markdown*))
         (root (asdf:system-source-directory "libtmux"))
         (script (libtmux.scripts.examples:tutorial-script root forms)))
    (is (= 5 (length forms)))
    (is (< (search "(one)" script) (search "(two)" script) (search "(terminate-owned-server" script)))
    (is (null (search "Injected tutorial failure" script)))
    (is (search "Injected tutorial failure"
                (libtmux.scripts.examples:tutorial-script root forms :inject-failure t)))
    (signals libtmux.scripts:script-failure
      (libtmux.scripts.examples:tutorial-script root (butlast forms)))))
