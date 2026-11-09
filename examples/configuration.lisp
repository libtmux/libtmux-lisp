(require :asdf)
(asdf:load-asd (truename (merge-pathnames "../libtmux.asd" *load-truename*)))
(asdf:load-system "libtmux")

;;; docs:decodedconfiguration
(defun inspect-configuration (&key (program "tmux"))
  "Return owned option, hook and environment records from an isolated daemon."
  (libtmux:with-daemon (daemon :program program)
    (libtmux:with-client (client :program (libtmux:daemon-program daemon)
                                 :socket-path (libtmux:daemon-socket-path daemon))
      (libtmux:new-session client :name "configuration" :command '("/bin/cat"))
      (let ((session (aref (libtmux:fetch-sessions client) 0)))
        (libtmux:set-option client "renumber-windows" nil :scope :session :target session)
        (libtmux:set-option client "@project" "editor" :scope :global-session)
        (libtmux:set-hook client "after-new-window" "display-message ready" :scope :session :target session)
        (libtmux:set-environment client "PROJECT_TOKEN" "local-only" :scope :session :target session :hidden t)
        (list :options (libtmux:show-options client :scope :session :target session
                                                   :names '("renumber-windows" "@project" "@absent"))
              :hooks (libtmux:show-hooks client :scope :session :target session
                                               :names '("after-new-window"))
              :environment (libtmux:show-environment client :scope :session :target session
                                                           :names '("PROJECT_TOKEN")))))))
;;; docs:end

(let* ((report (inspect-configuration :program (or (uiop:getenv "LIBTMUX_PROGRAM") "tmux")))
       (options (getf report :options))
       (environment (aref (getf report :environment) 0)))
  (assert (getf (aref options 0) :present-p))
  (assert (null (getf (aref options 0) :value)))
  (assert (getf (aref options 1) :inherited-p))
  (assert (equal "editor" (getf (aref options 1) :value)))
  (assert (not (getf (aref options 2) :present-p)))
  (assert (= 1 (length (getf (aref (getf report :hooks) 0) :value))))
  (assert (eq :present (getf environment :state)))
  (assert (getf environment :hidden-p))
  (assert (equal "local-only" (getf environment :value)))
  (assert (zerop (length (libtmux:pending-daemon-cleanups))))
  (format t "CONFIGURATION PASS: false, inheritance, absence, hooks and hidden environment~%"))
