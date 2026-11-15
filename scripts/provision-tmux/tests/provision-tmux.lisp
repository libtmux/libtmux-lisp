(in-package #:libtmux.tests)

(in-suite scripts)

(defun manifest-fixture (&rest overrides)
  (let ((cell (libtmux.scripts:obj
               "tmux" "3.8" "commit" (make-string 40 :initial-element #\a)
               "archive_url" (format nil "https://codeload.github.com/tmux/tmux/tar.gz/~A"
                                    (make-string 40 :initial-element #\a))
               "archive_sha256" (make-string 64 :initial-element #\b) "purpose" "supported")))
    (loop for (key value) on overrides by #'cddr do (libtmux.scripts:jset cell key value))
    (libtmux.scripts:obj "cells" (vector cell))))

(test provisioning-accepts-only-fully-pinned-manifest-cells
  (is (equal "3.8" (libtmux.scripts:jref
                    (libtmux.scripts.provision-tmux:manifest-cell (manifest-fixture) "3.8") "tmux")))
  (dolist (broken (list (manifest-fixture "commit" "abc")
                        (manifest-fixture "archive_sha256" "")
                        (manifest-fixture "archive_url" "https://example.invalid/tmux.tar.gz")))
    (signals libtmux.scripts:script-failure
      (libtmux.scripts.provision-tmux:manifest-cell broken "3.8")))
  (signals libtmux.scripts:script-failure
    (libtmux.scripts.provision-tmux:manifest-cell (manifest-fixture) "3.7")))

(test provisioned-binaries-must-be-x86-64-elf-and-the-key-names-the-build
  (is (libtmux.scripts.provision-tmux:elf-x86-64-p
       (uiop:native-namestring sb-ext:*runtime-pathname*)))
  (is (not (libtmux.scripts.provision-tmux:elf-x86-64-p
            (uiop:native-namestring (asdf:system-relative-pathname "libtmux" "libtmux.asd")))))
  (let ((identity (libtmux.scripts:obj "compiler" "cc 1" "packages" (vector "a=1"))))
    (is (string= (libtmux.scripts.provision-tmux:cache-key "3.8" identity)
                 (libtmux.scripts.provision-tmux:cache-key "3.8" identity)))
    (is (string/= (libtmux.scripts.provision-tmux:cache-key "3.8" identity)
                  (libtmux.scripts.provision-tmux:cache-key
                   "3.8" (libtmux.scripts:obj "compiler" "cc 2" "packages" (vector "a=1")))))))
