(in-package #:libtmux.internal)

(defun observed-link (capture session-id index window-id)
  (or (find (list session-id index window-id) (captured-collection capture :window-link)
            :key #'libtmux:id :test #'equal)
      (error 'libtmux:stale-target :message "The resulting window link is no longer present")))

(defun relocate-link (client source session index command detached observe options)
  (let ((source-target (link-target source))
        (destination (session-index-target session index))
        (expected-window (third (libtmux:id source))))
    (apply #'perform-command client (list source session)
           (append (list command "-s" source-target "-t" destination) (when detached '("-d")))
           :observe (when observe
                      (lambda (outcome capture)
                        (declare (ignore outcome))
                        (values (observed-link capture (libtmux:id session) index expected-window) t)))
           options)))

(defun relocate-pane (client source destination command direction size percent before full-size detached observe options)
  (apply #'perform-command client (list source destination)
         (append (list command "-s" (physical-target source :pane)
                       "-t" (physical-target destination :pane))
                 (split-flags direction size percent before full-size detached))
         :observe (when observe (observe-target client source)) options))

(in-package #:libtmux)

(defun link-window (client source-link session index &key (detached t) (observe t)
                                                         cancel-token timeout output-limit)
  "Link SOURCE-LINK's physical window into SESSION at the free INDEX.
Return a COMMAND-OUTCOME with the new window link when OBSERVE is true.
SOURCE-LINK preserves the source session context, including tmux group rules.
DETACHED defaults true. Never overwrites an occupied index. Signals STALE-TARGET
or an operational condition; observation failure is retained separately."
  (libtmux.internal::relocate-link
   client source-link session index "link-window" detached observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun move-window (client source-link session index &key (detached t) (observe t)
                                                         cancel-token timeout output-limit)
  "Move SOURCE-LINK into SESSION at the free INDEX; return a COMMAND-OUTCOME.
Other links to the physical window survive. Removing a session's last link can
destroy that session, following tmux semantics. OBSERVE supplies the destination
link. DETACHED defaults true; occupied indexes are never overwritten. Signals
STALE-TARGET or an operational condition; older link observations stay unchanged."
  (libtmux.internal::relocate-link
   client source-link session index "move-window" detached observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun unlink-window (client link &key kill-if-last cancel-token timeout output-limit)
  "Remove the captured LINK and return a COMMAND-OUTCOME without a value.
Tmux refuses the last reference unless KILL-IF-LAST is explicit; group membership
affects that check. Removing a last link can destroy its window and session.
Signals STALE-TARGET or an operational condition. Does not refresh a deleted link."
  (libtmux.internal::perform-command
   client (list link)
   (append (list "unlink-window" "-t" (libtmux.internal::link-target link))
           (when kill-if-last '("-k")))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun swap-windows (client first-link second-link &key select (observe t)
                                                       cancel-token timeout output-limit)
  "Swap physical windows at two captured links; return a COMMAND-OUTCOME.
OBSERVE supplies a fresh vector of replacement links in argument order. SELECT
selects the affected indexes in their sessions; omission keeps current indexes.
Tmux group restrictions apply. Signals STALE-TARGET or an operational condition;
old links retain their original expected window IDs."
  (let ((first-target (libtmux.internal::link-target first-link))
        (second-target (libtmux.internal::link-target second-link))
        (first-id (id first-link)) (second-id (id second-link)))
    (libtmux.internal::perform-command
     client (list first-link second-link)
     (append (list "swap-window" "-s" first-target "-t" second-target) (when select '("-d")))
     :observe (when observe
                (lambda (outcome capture)
                  (declare (ignore outcome))
                  (values (vector (libtmux.internal::observed-link
                                   capture (first first-id) (second first-id) (third second-id))
                                  (libtmux.internal::observed-link
                                   capture (first second-id) (second second-id) (third first-id))) t)))
     :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun move-pane (client source destination &key (direction :vertical) size percent before full-size
                                                (detached t) (observe t) cancel-token timeout output-limit)
  "Move SOURCE pane beside DESTINATION; return an outcome with the moved pane.
DIRECTION is :HORIZONTAL or :VERTICAL. SIZE is cells; PERCENT is 1..100,
mutually exclusive with SIZE. BEFORE changes placement and FULL-SIZE spans the
window. Percent sizing retains tmux's version semantics: with FULL-SIZE, 3.3a
uses destination-pane dimensions and 3.8 uses whole-window dimensions. Use SIZE
for cell-based control. DETACHED defaults true.
An emptied source window is destroyed, including all its links. With DETACHED
false, tmux chooses the session context of the physical destination. OBSERVE
supplies a replacement source pane; its old observation retains its old window.
Signals STALE-TARGET or an operational condition."
  (libtmux.internal::relocate-pane
   client source destination "move-pane" direction size percent before full-size detached observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun join-pane (client source destination &key (direction :vertical) size percent before full-size
                                                (detached t) (observe t) cancel-token timeout output-limit)
  "Join SOURCE pane beside DESTINATION using tmux's join-pane command.
Arguments, outcomes, emptied-window effects and observation semantics match
MOVE-PANE. Both targets are captured physical panes. Signals STALE-TARGET or an
operational condition; a failed follow-up is distinct from mutation failure."
  (libtmux.internal::relocate-pane
   client source destination "join-pane" direction size percent before full-size detached observe
   (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun break-pane (client pane source-link session index &key name (detached t) (observe t)
                                                            cancel-token timeout output-limit)
  "Break PANE from SOURCE-LINK into SESSION's free INDEX; return an outcome.
SOURCE-LINK fixes the session context when breaking the window's only pane;
tmux moves that link instead of creating another physical window. NAME is
literal. DETACHED defaults true. OBSERVE supplies the destination window link.
The pane keeps its identity. Signals INVALID-ARGUMENT, STALE-TARGET or an
operational condition. Occupied indexes are never overwritten."
  (let ((pane-id (libtmux.internal::physical-target pane :pane))
        (source (libtmux.internal::link-target source-link))
        (destination (libtmux.internal::session-index-target session index)))
    (unless (same-entity-p (window pane) (window source-link))
      (libtmux.internal::invalid-argument "Pane and source link must refer to the same captured physical window"))
    (libtmux.internal::perform-command
     client (list pane source-link session)
     (append (list "break-pane" "-s" (concatenate 'string source "." pane-id) "-t" destination)
             (when detached '("-d")) (when name (list "-n" (libtmux.internal::text-argument name "Window name"))))
     :observe (when observe
                (lambda (outcome capture)
                  (declare (ignore outcome))
                  (let ((moved (libtmux.internal::resolve-observation client pane capture)))
                    (values (libtmux.internal::observed-link capture (id session) index (id (window moved))) t))))
     :cancel-token cancel-token :timeout timeout :output-limit output-limit)))

(defun swap-panes (client first-pane second-pane &key (detached t) preserve-zoom (observe t)
                                                     cancel-token timeout output-limit)
  "Swap two physical panes; return an outcome with replacements in a fresh vector.
The vector follows argument order. DETACHED defaults true; tmux still adjusts
active-pane references when panes change windows. PRESERVE-ZOOM restores zoom.
Signals STALE-TARGET or an operational condition. Earlier captures stay local
and unchanged; observation failure is retained separately."
  (libtmux.internal::perform-command
   client (list first-pane second-pane)
   (append (list "swap-pane" "-s" (libtmux.internal::physical-target first-pane :pane)
                 "-t" (libtmux.internal::physical-target second-pane :pane))
           (when detached '("-d")) (when preserve-zoom '("-Z")))
   :observe (when observe
              (lambda (outcome capture)
                (declare (ignore outcome))
                (values (vector (libtmux.internal::resolve-observation client first-pane capture)
                                (libtmux.internal::resolve-observation client second-pane capture)) t)))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun rotate-window (client window &key (direction :up) preserve-zoom (observe t)
                                        cancel-token timeout output-limit)
  "Rotate WINDOW's pane positions :UP or :DOWN; return an outcome and replacement.
Tmux also advances the active pane. PRESERVE-ZOOM restores zoom after rotating.
Signals INVALID-ARGUMENT, STALE-TARGET or an operational condition. Captured
pane order remains unchanged in earlier observations."
  (libtmux.internal::operate-on-target
   client window :window "rotate-window"
   (append (list (case direction (:up "-U") (:down "-D")
                   (otherwise (libtmux.internal::invalid-argument "Rotate direction must be :up or :down"))))
           (when preserve-zoom '("-Z")))
   observe (list :cancel-token cancel-token :timeout timeout :output-limit output-limit)))
