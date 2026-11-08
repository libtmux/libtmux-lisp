(in-package #:libtmux.tests)

(in-suite integration)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(test owned-daemon-survives-client-scopes-and-startup-cancellation
  "Live daemon lifecycle belongs in the outer loop; no existing server is used."
  (let* ((descriptors-before (length (directory "/proc/self/fdinfo/*")))
         (token (libtmux:make-cancellation-token))
         (owner (libtmux::start-daemon
                 :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                 :timeout 0.75 :output-limit 32768 :cancel-token token
                 :environment '("LC_ALL=C" "PATH=/usr/bin:/bin" "LIBTMUX_DAEMON_TEST=owned")))
         (socket (libtmux::daemon-socket-path owner))
         (program (libtmux::daemon-program owner))
         (before nil))
    (unwind-protect
         (progn
           (is (eq :ready (libtmux::daemon-state owner)))
           (libtmux:cancel token)
           (dotimes (visit 2)
             (libtmux:with-client (client :program program :socket-path socket :timeout 0.5)
               (let ((capture (libtmux:fetch-snapshot client)))
                 (is (= visit (length (libtmux:sessions capture))))
                 (when before (is (= (getf before :server/pid)
                                     (getf (libtmux:provenance capture) :server/pid))))
                 (setf before (libtmux:provenance capture)))
               (when (zerop visit)
                 (let ((outcome (libtmux:run-command client '("-N" "show-environment" "-g" "LC_ALL")
                                                   :effect :read)))
                   (is (string= (format nil "LC_ALL=C~%")
                                (libtmux.internal::strict-text (libtmux:outcome-stdout outcome)))))
                 (is (eq :succeeded
                         (libtmux:outcome-status
                          (libtmux:new-session client :name "owned" :command '("/bin/cat"))))))))
           (is (eq :ready (libtmux::daemon-state owner)))
           (libtmux::stop-daemon owner)
           (is (eq :closed (libtmux::daemon-state owner)))
           (is (not (probe-file socket)))
           (is (not (find owner (libtmux::pending-daemon-cleanups))))
           (libtmux::stop-daemon owner)
           (is (= descriptors-before (length (directory "/proc/self/fdinfo/*")))))
      (libtmux::stop-daemon owner))))

(test owned-daemon-startup-errors-release-resources-before-signalling
  "Live startup failure boundaries belong in the outer loop."
  (dolist (mode '(:cancelled :output-limit :gated-cancel :gated-exit :handoff-cancel :wrong-witness))
    (let* ((token (libtmux:make-cancellation-token))
           (condition nil)
           (libtmux.internal::*daemon-stage-hook*
             (lambda (stage owner)
               (cond ((and (eq stage :gated) (eq mode :gated-cancel)) (libtmux:cancel token))
                     ((and (eq stage :gated) (eq mode :gated-exit))
                      (libtmux.internal::signal-job-group
                       (slot-value owner 'libtmux.internal::job) sb-posix:sigkill))
                     ((and (eq stage :before-ready) (eq mode :handoff-cancel)) (libtmux:cancel token))
                     ((and (eq stage :socket-observed) (eq mode :wrong-witness))
                      (incf (slot-value owner 'libtmux.internal::pid)))))))
      (when (eq mode :cancelled) (libtmux:cancel token))
      (handler-case
          (libtmux:start-daemon :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                :timeout 0.75 :output-limit (if (eq mode :output-limit) 2 32768)
                                :cancel-token token)
        (libtmux:daemon-start-failed (caught) (setf condition caught)))
      (is (typep condition 'libtmux:daemon-start-failed))
      (when condition
        (let* ((owner (libtmux:error-daemon condition))
               (socket (libtmux:daemon-socket-path owner))
               (job (slot-value owner 'libtmux.internal::job)))
          (unwind-protect
               (progn
                 (is (eq :closed (libtmux:daemon-state owner)))
                 (is (not (find owner (libtmux:pending-daemon-cleanups))))
                 (is-true (or (null socket) (not (probe-file socket))))
                 (when job
                   (is (null (libtmux.internal::process-job-pidfd job)))
                   (when (libtmux.internal::process-job-process job)
                     (is (not (uiop:process-alive-p (libtmux.internal::process-job-process job)))))))
            (libtmux:stop-daemon owner)))))))

(test owned-daemon-scopes-retain-failed-unreturned-owners
  "Nonlocal startup exits must leave retrievable cleanup responsibility."
  (let ((socket nil) (original nil))
    (is (equal '(:first nil :last)
               (multiple-value-list
                (libtmux:with-daemon (owner :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                           :timeout 0.75)
                  (setf socket (libtmux:daemon-socket-path owner) original owner owner nil)
                  (values :first nil :last)))))
    (is (eq :closed (libtmux:daemon-state original)))
    (is (not (probe-file socket))))
  (progv '(scope-owner) '(:outer)
    (let ((returned
            (libtmux:with-daemon (scope-owner
                                 :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux") :timeout 0.75)
              (declare (special scope-owner))
              scope-owner)))
      (is (typep returned 'libtmux:daemon))
      (is (eq :closed (libtmux:daemon-state returned)))
      (is (eq :outer (symbol-value 'scope-owner)))))
  (let ((socket nil) (armed nil) (pending-before (libtmux:pending-daemon-cleanups)))
    (let ((libtmux.internal::*child-signaller*
            (lambda (&rest arguments)
              (if (and armed (= (second arguments) sb-posix:sigkill))
                  (error "Injected final cleanup failure")
                  (apply #'libtmux.internal::pidfd-signal arguments))))
          (libtmux.internal::*daemon-stage-hook*
            (lambda (stage owner)
              (when (eq stage :socket-observed)
                (setf socket (libtmux:daemon-socket-path owner) armed t)
                (throw 'leave :preserved)))))
      (is (eq :preserved
              (catch 'leave
                (libtmux:start-daemon :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux")
                                      :timeout 0.75)))))
    (let ((owners (remove-if (lambda (owner) (find owner pending-before))
                             (libtmux:pending-daemon-cleanups))))
      (is (= 1 (length owners)))
      (when (= 1 (length owners))
        (let ((owner (aref owners 0)))
          (is (string= socket (libtmux:daemon-socket-path owner)))
          (is (plusp (length (libtmux:daemon-cleanup-failures owner))))
          (libtmux:stop-daemon owner)
          (is (eq :closed (libtmux:daemon-state owner)))
          (is (not (probe-file socket)))
          (is (not (find owner (libtmux:pending-daemon-cleanups)))))))))

(test owned-daemon-refuses-a-substituted-socket
  "Shutdown uses retained child authority and refuses a replacement endpoint."
  (let* ((owner (libtmux:start-daemon
                 :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux") :timeout 0.75))
         (socket (libtmux:daemon-socket-path owner))
         (original (concatenate 'string socket ".original"))
         (replacement (make-instance 'sb-bsd-sockets:local-socket :type :stream :protocol 0)))
    (unwind-protect
         (progn
           (sb-posix:rename socket original)
           (sb-bsd-sockets:socket-bind replacement socket)
           (signals libtmux:daemon-cleanup-failed (libtmux:stop-daemon owner))
           (is (probe-file socket))
           (is (find owner (libtmux:pending-daemon-cleanups)))
           (sb-bsd-sockets:socket-close replacement)
           (setf replacement nil)
           (sb-posix:unlink socket)
           (sb-posix:rename original socket)
           (libtmux:stop-daemon owner)
           (is (eq :closed (libtmux:daemon-state owner)))
           (is (not (probe-file socket))))
      (when replacement (sb-bsd-sockets:socket-close replacement))
      (when (probe-file original)
        (when (probe-file socket) (sb-posix:unlink socket))
        (sb-posix:rename original socket))
      (libtmux:stop-daemon owner))))

(test owned-daemon-retries-wake-failures-and-aborted-workers
  "Retry must recover ownership after an admission error or an aborted worker."
  (let* ((owner (make-instance 'libtmux:daemon :program "unused"))
         (token (slot-value owner 'libtmux.internal::lifetime-token))
         (job (libtmux.internal::make-process-job :token token))
         (bad (sb-posix:open "/dev/null" sb-posix:o-rdonly))
         (wake (libtmux.internal::cancellation-event-open)))
    (setf (slot-value owner 'libtmux.internal::startup-active) nil
          (slot-value owner 'libtmux.internal::state) :ready
          (slot-value owner 'libtmux.internal::job) job
          (slot-value owner 'libtmux.internal::job-wake) bad)
    (unwind-protect
         (progn
           (signals libtmux:daemon-cleanup-failed (libtmux:stop-daemon owner))
           (is (find owner (libtmux:pending-daemon-cleanups)))
           (is (libtmux:cancelled-p token))
           (setf (slot-value owner 'libtmux.internal::job-wake) wake)
           (libtmux:stop-daemon owner)
           (is (equal '(:wake) (libtmux.internal::poll-owned (list (list :wake wake :input)) 0)))
           (is (eq :closed (libtmux:daemon-state owner)))
           (is (not (find owner (libtmux:pending-daemon-cleanups)))))
      (setf (slot-value owner 'libtmux.internal::job-wake) nil)
      (libtmux:stop-daemon owner)
      (sb-posix:close bad)
      (sb-posix:close wake)))
  (let ((owner (make-instance 'libtmux:daemon :program "unused")))
    (setf (slot-value owner 'libtmux.internal::startup-active) nil
          (slot-value owner 'libtmux.internal::worker)
          (sb-thread:make-thread (lambda () (sb-thread:abort-thread))))
    (libtmux:stop-daemon owner)
    (is (eq :closed (libtmux:daemon-state owner)))
    (is (typep (libtmux:daemon-failure owner) 'libtmux:command-failed))
    (is (not (find owner (libtmux:pending-daemon-cleanups))))))

(test owned-daemon-never-recloses-retired-descriptor-numbers
  "A close error cannot grant a retry authority over a reused numeric descriptor."
  (let* ((owner (make-instance 'libtmux:daemon :program "unused"))
         (retired (libtmux.internal::cancellation-event-open))
         (replacement nil))
    (setf (slot-value owner 'libtmux.internal::startup-active) nil
          (slot-value owner 'libtmux.internal::notify) retired)
    (sb-posix:close retired)
    (unwind-protect
         (progn
           (signals libtmux:daemon-cleanup-failed (libtmux:stop-daemon owner))
           (is (null (slot-value owner 'libtmux.internal::notify)))
           (setf replacement (libtmux.internal::cancellation-event-open))
           (is (= retired replacement))
           (libtmux:stop-daemon owner)
           (is (integerp (sb-posix:fcntl replacement sb-posix:f-getfd)))
           (is (eq :closed (libtmux:daemon-state owner))))
      (libtmux:stop-daemon owner)
      (when replacement (ignore-errors (sb-posix:close replacement))))))

(test owned-daemon-rejects-unprotected-parents-and-invalid-watches
  "Endpoint ownership and watch loss fail closed without launching tmux."
  (let ((directory (sb-posix:mkdtemp "/tmp/libtmux-lisp-parent-XXXXXX")))
    (unwind-protect
         (progn
           (sb-posix:chmod directory #o777)
           (signals libtmux:invalid-argument
             (libtmux.internal::bootstrap-parent directory))
           (sb-posix:chmod directory #o700)
           (is (string= (libtmux.internal::canonical-native-path directory)
                        (libtmux.internal::bootstrap-parent directory))))
      (sb-posix:rmdir directory)))
  (dolist (event '(#(1 0 0 0)
                   #(255 255 255 255 0 64 0 0 0 0 0 0 0 0 0 0)
                   #(2 0 0 0 4 0 0 0 0 0 0 0 0 0 0 0)
                   #(1 0 0 0 4 0 0 0 0 0 0 0 3 0 0 0)))
    (multiple-value-bind (reader writer) (sb-posix:pipe)
      (let ((owner (make-instance 'libtmux:daemon :program "unused")))
        (unwind-protect
             (progn
               (setf (slot-value owner 'libtmux.internal::notify) reader
                     (slot-value owner 'libtmux.internal::watch) 1)
               (libtmux.internal::raw-write writer (libtmux.internal::octet-vector event))
               (signals libtmux:libtmux-error
                 (libtmux.internal::read-daemon-notifications owner)))
          (sb-posix:close reader)
          (sb-posix:close writer))))))

(test owned-daemon-close-during-startup
  "Concurrent startup and close synchronize through events, not polling sleeps."
  (let* ((gated (sb-thread:make-semaphore))
         (release (sb-thread:make-semaphore))
         (owner nil) (constructor nil) (closer nil) (start-failure nil) (close-failure nil)
         (hook (lambda (stage acquired)
                 (when (eq stage :gated)
                   (setf owner acquired)
                   (sb-thread:signal-semaphore gated)
                   (unless (sb-thread:wait-on-semaphore release :timeout 0.75)
                     (error "Test did not release the startup gate"))))))
    (unwind-protect
         (progn
           (setf constructor
                 (sb-thread:make-thread
                  (lambda ()
                    (let ((libtmux.internal::*daemon-stage-hook* hook))
                      (handler-case
                          (libtmux:start-daemon
                           :program (or (uiop:getenv "LIBTMUX_TEST_TMUX") "tmux") :timeout 0.75)
                        (error (condition) (setf start-failure condition)))))))
           (is (sb-thread:wait-on-semaphore gated :timeout 0.75))
           (when owner
             (setf closer
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case (libtmux:stop-daemon owner)
                        (error (condition) (setf close-failure condition))))))
             (is (equal '(:state)
                        (libtmux.internal::poll-owned
                         (list (list :state (slot-value owner 'libtmux.internal::event) :input)) 0.75)))
             (sb-thread:signal-semaphore release)
             (sb-thread:join-thread constructor :timeout 0.75)
             (sb-thread:join-thread closer :timeout 0.75)
             (is (typep start-failure 'libtmux:daemon-start-failed))
             (is (null close-failure))
             (is (eq :closed (libtmux:daemon-state owner)))
             (is (not (find owner (libtmux:pending-daemon-cleanups))))))
      (sb-thread:signal-semaphore release)
      (when constructor (sb-thread:join-thread constructor :timeout 0.75))
      (when closer (sb-thread:join-thread closer :timeout 0.75))
      (when owner (libtmux:stop-daemon owner)))))
