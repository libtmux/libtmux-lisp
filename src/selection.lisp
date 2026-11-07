(in-package #:libtmux.internal)

(defun cycle-selection (client target model command activity observe options)
  (apply #'perform-command client (list target)
         (append (list command "-t" (physical-target target model)) (when activity '("-a")))
         :observe (when observe
                    (lambda (outcome capture)
                      (declare (ignore outcome))
                      (let* ((parent (resolve-observation client target capture))
                             (children (ecase model
                                         (:session (libtmux:window-links parent))
                                         (:window (libtmux:panes parent))))
                             (selected (find-if #'libtmux:active-p children)))
                        (unless selected
                          (error 'libtmux:incomplete-snapshot :message "No active selection after the command"))
                        (values selected t)))) options))

(in-package #:libtmux)

(defun next-window (client session &key activity (observe t) cancel-token timeout output-limit)
  "Select SESSION's next window link; return a COMMAND-OUTCOME.
ACTIVITY restricts selection to windows with an alert. OBSERVE supplies the
newly captured active link through OUTCOME-VALUE, or records an observation
failure separately. Signals STALE-TARGET or an operational condition."
  (libtmux.internal::cycle-selection
   client session :session "next-window" activity observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun previous-window (client session &key activity (observe t) cancel-token timeout output-limit)
  "Select SESSION's previous window link; return a COMMAND-OUTCOME.
ACTIVITY restricts selection to windows with an alert. OBSERVE supplies the
newly captured active link through OUTCOME-VALUE, or records an observation
failure separately. Signals STALE-TARGET or an operational condition."
  (libtmux.internal::cycle-selection
   client session :session "previous-window" activity observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun last-window (client session &key (observe t) cancel-token timeout output-limit)
  "Select SESSION's last active link; return an outcome with that observed link.
OBSERVE may omit follow-up acquisition. Tmux reports an error when no last
window exists. Signals STALE-TARGET or an operational condition. Earlier
captures retain their original selection."
  (libtmux.internal::cycle-selection
   client session :session "last-window" nil observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun last-pane (client window &key (observe t) cancel-token timeout output-limit)
  "Select WINDOW's last active pane; return an outcome with that observed pane.
OBSERVE may omit follow-up acquisition. Tmux reports an error when no last
pane exists. Signals STALE-TARGET or an operational condition. Earlier
captures retain their original selection."
  (libtmux.internal::cycle-selection
   client window :window "last-pane" nil observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))
