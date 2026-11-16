(in-package #:libtmux.internal)

(defparameter *capability-registry*
  '((:feature :named-buffer-deletion :name "Named buffer deletion"
     :summary "Delete a selected paste buffer by name." :minimum-version "3.4"
     :apis ("libtmux:delete-buffer") :commands ((:name "delete-buffer" :flags ("-b"))))
    (:feature :literal-message-flag :name "Literal message flag"
     :summary "Print a message without expanding tmux formats." :minimum-version "3.4" :fallback :escaped-format
     :apis ("libtmux:display-message") :commands ((:name "display-message" :flags ("-l"))))
    (:feature :verbatim-paste-flag :name "Verbatim paste flag"
     :summary "Paste without bracketed-paste markers." :minimum-version "3.7" :fallback :raw-paste
     :apis ("libtmux:paste-buffer") :commands ((:name "paste-buffer" :flags ("-S"))))
    (:feature :key-listing-format :name "Formatted key listings"
     :summary "Choose the format used to print key bindings." :minimum-version "3.7"
     :apis ("libtmux:list-keys") :commands ((:name "list-keys" :flags ("-F"))))
    (:feature :group-server-access :name "Group server access"
     :summary "Inspect or change access for a Unix group." :minimum-version "3.8"
     :apis ("libtmux:server-access") :commands ((:name "server-access" :flags ("-g"))))
    (:feature :wait-channel-disconnect-cleanup :name "Wait channel cleanup"
     :summary "Release blocked wait and lock operations when their client disconnects." :minimum-version "3.8"
     :apis ("libtmux:wait-for") :commands ((:name "wait-for" :flags ("-L"))))
    (:feature :control :name "Persistent control connection"
     :summary "Submit bounded requests and receive pane output on one worker-owned connection." :minimum-version "3.8"
     :apis ("libtmux.control:open-connection" "libtmux.control:reconnect")
     :commands ((:name "tmux" :flags ("-C")) (:name "attach-session" :flags ("-E" "-t"))))
    (:feature :json-layout :name "JSON window layouts"
     :summary "Apply a window layout represented as JSON." :minimum-version "3.8"
     :apis ("libtmux:select-layout") :commands ((:name "select-layout" :flags ())))
    (:feature :option-listing-format :name "Formatted option listings"
     :summary "Choose the format used by the native option printer." :minimum-version "3.8"
     :apis ("libtmux:show-options-text") :commands ((:name "show-options" :flags ("-F"))))
    (:feature :hook-listing-format :name "Formatted hook listings"
     :summary "Choose the format used by the native hook printer." :minimum-version "3.8"
     :apis ("libtmux:show-hooks-text") :commands ((:name "show-hooks" :flags ("-F"))))
    (:feature :hook-monitor-listing :name "Hook monitor listings"
     :summary "Include hook monitors in native hook inspection." :minimum-version "3.8"
     :apis ("libtmux:show-hooks-text") :commands ((:name "show-hooks" :flags ("-B"))))))

(defun capability-entry (feature)
  (or (find feature *capability-registry* :key (lambda (entry) (getf entry :feature)))
      (invalid-argument "Unknown capability ~S; inspect CAPABILITY-FEATURES" feature)))

(defun feature-supported-p (version feature)
  (version-at-least-p version (getf (capability-entry feature) :minimum-version)))

(defun report-from-provenance (provenance)
  (let ((version (supported-version (getf provenance :server/version))))
    (make-instance 'libtmux:capability-report :version version
      :provenance (owned-data provenance)
      :features (map 'vector
                     (lambda (entry)
                       (let ((supported (feature-supported-p version (getf entry :feature))))
                         (append (owned-data entry)
                                 (list :supported-p supported
                                       :handling (if supported :native (or (getf entry :fallback) :reject))))))
                     *capability-registry*))))

(in-package #:libtmux)

(defclass capability-report ()
  ((version :initarg :version)
   (provenance :initarg :provenance)
   (features :initarg :features))
  (:documentation "A retained observation of one daemon and the library's version gates.
Readers return owned values without I/O. The report survives client cleanup and
does not grant operation authority or refresh captured targets. Exact option,
field and workspace schemas retain their independent source-qualified checks.
See also: CAPABILITIES, CAPABILITY, SUPPORTS-P, CAPABILITY-PROVENANCE."))

(defun capability-version (report)
  "Return an owned copy of REPORT's observed daemon release. No I/O.
This is not the executable release returned by TMUX-VERSION.
See also: CAPABILITIES, CAPABILITY-PROVENANCE."
  (check-type report capability-report)
  (copy-seq (slot-value report 'version)))

(defun capability-provenance (report)
  "Return an owned plist of REPORT's daemon identity. No I/O.
Keys are :SERVER/PID, :SERVER/START-TIME, :SERVER/SOCKET-PATH, :SERVER/VERSION,
:SERVER/SOCKET-DEVICE, :SERVER/SOCKET-INODE and :SERVER/PROCESS-START. These
describe acquisition; they do not prove that the daemon is still alive.
See also: CAPABILITY-VERSION, CAPABILITIES."
  (check-type report capability-report)
  (libtmux.internal::owned-data (slot-value report 'provenance)))

(defun capability-features (report)
  "Return an owned vector of REPORT's feature plists in registry order. No I/O.
Each has :FEATURE, :NAME, :SUMMARY, :MINIMUM-VERSION, :APIS, :COMMANDS, :SUPPORTED-P and
:HANDLING; :FALLBACK appears when the operation has an older-daemon path.
:COMMANDS contains name/flags plists. :HANDLING is :NATIVE, :REJECT,
:ESCAPED-FORMAT or :RAW-PASTE. A flag can be unsupported while its operation
uses the stated fallback. Requirements describe this port's implemented API,
not the first tmux release that offered a lower-level command.
See also: CAPABILITY, SUPPORTS-P."
  (check-type report capability-report)
  (libtmux.internal::owned-data (slot-value report 'features)))

(defun capability (report feature)
  "Return an owned feature plist from REPORT, or signal INVALID-ARGUMENT.
FEATURE is a keyword from CAPABILITY-FEATURES. This local lookup does no I/O;
an unknown feature never looks like an unsupported known feature.
See also: CAPABILITY-FEATURES, SUPPORTS-P."
  (check-type report capability-report)
  (let ((entry (find feature (slot-value report 'features)
                     :key (lambda (item) (getf item :feature)))))
    (unless entry
      (libtmux.internal::invalid-argument "Unknown capability ~S; inspect CAPABILITY-FEATURES" feature))
    (libtmux.internal::owned-data entry)))

(defun supports-p (report feature)
  "Return whether REPORT's daemon meets FEATURE's native version requirement.
Unknown names signal INVALID-ARGUMENT. No I/O or configuration permission
check occurs; operations still validate their live targets and exact schemas.
See also: CAPABILITY, CAPABILITIES."
  (getf (capability report feature) :supported-p))

(defun capabilities (client &key cancel-token
                                 (timeout (slot-value client 'timeout))
                                 (output-limit (slot-value client 'output-limit)))
  "Observe CLIENT's responding daemon and return an owned CAPABILITY-REPORT.
Blocks under CLIENT's single-operation lease. TIMEOUT bounds total native
reads in seconds; OUTPUT-LIMIT bounds their combined stdout/stderr. CANCEL-TOKEN
and closing the client stop owned work through the normal transport.

Starts no daemon, invokes no after-hooks and does not change cached executable
version, captured generation or target authority. The built-in list-commands
bootstrap spelling is trusted: its configured command-alias override may run
arbitrary server code. Discovery does not audit aliases through show-options,
which can itself run after-hooks. Each call observes the selected endpoint; a saved report remains historical after replacement.

Closed/busy clients, cancellation, deadlines, byte limits, malformed records,
unsupported releases and lost continuity signal the existing typed conditions.
Temporary process witnesses close before return. No failure returns a fallback
report. See also: CAPABILITY, CAPABILITY-PROVENANCE, FETCH-SNAPSHOT."
  (check-type client client)
  (libtmux.internal::check-limits timeout output-limit)
  (handler-bind ((libtmux-error (lambda (condition) (setf (slot-value condition 'client) client))))
    (libtmux.internal::call-with-operation
     client cancel-token
     (lambda (token)
       (let* ((start (libtmux.internal::monotonic-seconds))
              (budget (libtmux.internal::make-capture-budget
                       :start start :deadline (+ start timeout) :remaining output-limit
                       :row-limit 1 :field-limit 8192))
              (witness nil))
         (unwind-protect
              (progn
                (let ((rows (libtmux.internal::capture-command client :witness token budget)))
                  (unless (= 1 (length rows))
                    (libtmux.internal::inconsistent-capture "Expected exactly one capability witness"))
                  (setf witness (libtmux.internal::witness-from-row client (aref rows 0))))
                (libtmux.internal::check-capture-budget budget token)
                (libtmux.internal::report-from-provenance
                 (libtmux.internal::witness-provenance witness)))
           (libtmux.internal::close-witness witness)))))))
