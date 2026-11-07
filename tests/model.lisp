(in-package #:libtmux.tests)

(in-suite unit)

(defun synthetic-rows (model rows)
  (libtmux.internal::decode-rows
   model (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                (mapcar #'record-bytes rows))))

(defun synthetic-snapshot (&key (context (gensym "SERVER-")) (generation 1) conflict)
  (libtmux.internal::build-snapshot
   context generation '(:server/socket-path "owned.sock" :server/version "3.8")
   (synthetic-rows :session '(("session/1" "$1" "a" "1" "0" "2")
                               ("session/1" "$2" "b" "1" "0" "1")))
   (synthetic-rows :window-link
                   '(("window-link/1" "$1" "0" "@3" "shared" "120" "30" "2" "1" "")
                     ("window-link/1" "$1" "2" "@3" "shared" "120" "30" "2" "0" "")
                     ("window-link/1" "$2" "7" "@3" "shared" "120" "30" "2" "1" "")))
   (synthetic-rows :pane
     (loop for (session index) in '(("$1" "0") ("$1" "2") ("$2" "7"))
           append (list (list "pane/1" session index "@3" "%255" "0" "1" "120" "15"
                              (if (and conflict (equal index "7")) "NVIM" "nvim")
                              "/srv/λ" "editor" "100" "0" "nvim")
                        (list "pane/1" session index "@3" "%256" "1" "0" "120" "15"
                              "sh" "" "" "0" "0" ""))))
   (synthetic-rows :client
                   '(("client/1" "pipe" "50" "1" "" "$1" "1" "0")
                     ("client/1" "pipe" "50" "1" "" "$1" "1" "0")))))

(test captured-graph-links-and-owned-data
  (let* ((libtmux.internal::*process-launched-hook*
           (lambda (job) (declare (ignore job)) (error "Local captured work launched a process")))
         (snapshot (synthetic-snapshot))
         (session (aref (libtmux:sessions snapshot) 0))
         (window (aref (libtmux:windows snapshot) 0))
         (pane (aref (libtmux:panes snapshot) 0))
         (links (libtmux:window-links snapshot)))
    (is (= 2 (length (libtmux:sessions snapshot))))
    (is (= 1 (length (libtmux:windows snapshot))))
    (is (= 2 (length (libtmux:panes snapshot))))
    (is (= 3 (length links)))
    (is (= 2 (length (libtmux:windows session))))
    (is (eq (aref (libtmux:windows session) 0) (aref (libtmux:windows session) 1)))
    (is (not (libtmux:same-entity-p (aref links 0) (aref links 1))))
    (is (eq window (libtmux:window pane)))
    (is (equal '(nil t) (multiple-value-list (libtmux:active-p (aref links 1)))))
    (is (= 2 (length (libtmux:clients session))))
    (is (not (libtmux:same-entity-p (aref (libtmux:clients session) 0)
                                   (aref (libtmux:clients session) 1))))
    (setf (aref links 0) nil)
    (is (typep (aref (libtmux:window-links snapshot) 0) 'libtmux:window-link))
    (setf (char (libtmux:name window) 0) #\X)
    (let ((data (libtmux:entity-data pane)))
      (setf (char (getf data :pane/current-command) 0) #\X)
      (is (equal "nvim" (libtmux:current-command pane)))
      (is (listp (getf data :pane/window))))
    (is (equal "shared" (libtmux:name window)))
    (is (stringp (princ-to-string pane)))
    (signals libtmux:field-unavailable (libtmux:field-value pane :window/name))))

(test identity-across-captures-and-generations
  (let* ((context (gensym "SERVER-"))
         (a (synthetic-snapshot :context context))
         (b (synthetic-snapshot :context context))
         (replacement (synthetic-snapshot :context context :generation 2))
         (other (synthetic-snapshot)))
    (is (libtmux:same-entity-p (aref (libtmux:panes a) 0) (aref (libtmux:panes b) 0)))
    (is (not (libtmux:same-entity-p (aref (libtmux:panes a) 0) (aref (libtmux:panes replacement) 0))))
    (is (not (libtmux:same-entity-p (aref (libtmux:panes a) 0) (aref (libtmux:panes other) 0))))
    (is (not (libtmux:same-entity-p (aref (libtmux:clients a) 0) (aref (libtmux:clients b) 0)))))
  (signals libtmux:incomplete-snapshot (synthetic-snapshot :conflict t))
  (let ((empty (libtmux.internal::build-snapshot (gensym) 1 nil #() #() #() #())))
    (is (equalp #() (libtmux:panes empty)))
    (is (not (eq (libtmux:panes empty) (libtmux:panes empty))))))
