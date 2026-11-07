(in-package #:libtmux.tests)

(in-suite regex)

(defun regex-filter (form)
  (libtmux.query:compile-filter :pane form))

(defun first-synthetic-pane ()
  (aref (libtmux:panes (synthetic-snapshot)) 0))

(test regex-search-and-full-match-remain-distinct
  (let ((pane (first-synthetic-pane)))
    (is (funcall (libtmux.query:predicate
                  (regex-filter
                   '(:regex-search :pane/current-command
                     (:cl-ppcre "^NV" :case-insensitive-mode t))))
                 pane))
    (is (funcall (libtmux.query:predicate
                  (regex-filter
                   '(:regex-search :pane/current-command
                     (:cl-ppcre "vim"))))
                 pane))
    (is (not (funcall (libtmux.query:predicate
                       (regex-filter
                        '(:regex-full-match :pane/current-command
                          (:cl-ppcre "vim"))))
                      pane)))
    (is (funcall (libtmux.query:predicate
                  (regex-filter
                   '(:regex-full-match :pane/current-command
                     (:cl-ppcre "nvim"))))
                 pane))))

(test regex-full-match-backtracks-to-the-whole-input
  (let ((pane (first-synthetic-pane)))
    (is (funcall (libtmux.query:predicate
                  (regex-filter
                   '(:regex-full-match :pane/current-command
                     (:cl-ppcre "n|nvim"))))
                 pane))
    (is (funcall (libtmux.query:predicate
                  (regex-filter
                   '(:regex-full-match :pane/current-command
                     (:cl-ppcre ".*?"))))
                 pane))
    (is (funcall (libtmux.query:predicate
                  (regex-filter
                   '(:regex-full-match :pane/current-command
                     (:cl-ppcre "nvim # exact command"
                      :extended-mode t))))
                 pane))
    (is (funcall (libtmux.query:predicate
                  (regex-filter
                   '(:regex-full-match :pane/current-command
                     (:cl-ppcre "(?-x)nvim" :extended-mode t))))
                 pane))))

(test regex-match-at-position-zero-and-absence
  (let* ((panes (libtmux:panes (synthetic-snapshot)))
         (position-zero
           (libtmux.query:predicate
            (regex-filter
             '(:regex-search :pane/current-command (:cl-ppcre "^n")))))
         (optional-path
           (libtmux.query:predicate
            (regex-filter
             '(:regex-search :pane/current-path (:cl-ppcre "^/srv"))))))
    (is (funcall position-zero (aref panes 0)))
    (is (funcall optional-path (aref panes 0)))
    (is (not (funcall optional-path (aref panes 1))))))

(test regex-input-is-owned-and-inspection-is-defensive
  (let* ((pattern (copy-seq "^nvim$"))
         (form (list :regex-full-match :pane/current-command
                     (list :cl-ppcre pattern :multi-line-mode nil)))
         (filter (regex-filter form))
         (pane (first-synthetic-pane))
         (inspection (libtmux.query:expression filter)))
    (setf (char pattern 1) #\x
          (char (second (third inspection)) 1) #\x)
    (is (funcall (libtmux.query:predicate filter) pane))
    (is (string= "^nvim$"
                 (second (third (libtmux.query:expression filter)))))))

(test regex-options-are-closed-and-typed
  (signals libtmux.query:invalid-filter
    (regex-filter
     '(:regex-search :pane/current-command #(:cl-ppcre "n"))))
  (signals libtmux.query:invalid-filter
    (regex-filter
     '(:regex-search :pane/current-command "xx")))
  (signals libtmux.query:invalid-filter
    (regex-filter
     '(:regex-search :pane/current-command (:cl-ppcre "n" :unknown t))))
  (signals libtmux.query:invalid-filter
    (regex-filter
     '(:regex-search :pane/current-command
       (:cl-ppcre "n" :case-insensitive-mode :yes))))
  (signals libtmux.query:invalid-filter
    (regex-filter
     '(:regex-search :pane/current-command
       (:cl-ppcre "n" :case-insensitive-mode t :case-insensitive-mode nil))))
  (signals libtmux.query:invalid-filter
    (regex-filter
     '(:regex-search :pane/current-command (:other "n"))))
  (signals libtmux.query:invalid-filter
    (regex-filter
     '(:regex-search :pane/width (:cl-ppcre "120")))))

(test regex-compilation-retains-parser-failure
  (handler-case
      (progn
        (regex-filter
         '(:regex-search :pane/current-command (:cl-ppcre "[")))
        (fail "Invalid CL-PPCRE pattern compiled"))
    (libtmux.query:invalid-filter (condition)
      (is (typep (libtmux:error-cause condition) 'condition)))))
