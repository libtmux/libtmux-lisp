(in-package #:libtmux.tests)

(in-suite scripts)

(defparameter *directory-intro*
  (format nil "A client reaches one tmux server.~%~%#### What is on here~%~%The groups:~%~%"))

(defun directory-row (title guidance &rest names)
  (format nil "**~A.** ~A~%~%~{`libtmux:~A`~^, ~}~%~%" title guidance names))

(defparameter *directory-rows*
  (list (directory-row "One" "Does one." "a")
        (directory-row "Two" "Does two." "b" "c")
        (directory-row "Three" "Does three." "d")))

(defun fold-directory (&rest rows)
  (libtmux.scripts.api-directory:fold
   (apply #'concatenate 'string *directory-intro* rows)))

(test three-bold-led-rows-fold-into-one-directory
  (multiple-value-bind (runs strays) (apply #'fold-directory *directory-rows*)
    (is (equal '((("One" ("libtmux:a")) ("Two" ("libtmux:b" "libtmux:c"))
                  ("Three" ("libtmux:d"))))
               runs))
    (is (null strays))))

(test directory-references-may-wrap-and-use-and
  (let ((runs (fold-directory
               (first *directory-rows*) (second *directory-rows*)
               (format nil "**Three.** Does three.~%~%`libtmux:d`,~%`libtmux:e` and~%`libtmux.query:f`~%"))))
    (is (equal '("libtmux:d" "libtmux:e" "libtmux.query:f")
               (second (third (first runs)))))))

(test prose-after-the-guidance-leaves-the-row-unfolded
  (multiple-value-bind (runs strays)
      (fold-directory (first *directory-rows*)
                      (format nil "**Two.** Does two.~%~%`libtmux:b` is also useful here.~%~%")
                      (third *directory-rows*))
    (is (null runs))
    (is (equal '("One" "Two" "Three") strays))))

(test fewer-than-three-rows-stay-prose
  (multiple-value-bind (runs strays)
      (fold-directory (first *directory-rows*) (second *directory-rows*))
    (is (null runs))
    (is (equal '("One" "Two") strays))))
