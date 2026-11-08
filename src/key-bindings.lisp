(in-package #:libtmux.internal)

(defun binding-command-source (command command-p source source-p)
  (when (eq command-p source-p)
    (invalid-argument "Specify exactly one of command argv or command-source"))
  (if source-p
      (text-argument source "Binding command source" nil)
      (let* ((arguments (argument-vector command))
             (name (when (plusp (length arguments)) (aref arguments 0))))
        (unless (and name (plusp (length name)))
          (invalid-argument "Binding command argv needs a nonempty command name"))
        ;; Tmux recognizes NAME=value after removing quotes from the first token.
        (when (find #\= name)
          (invalid-argument "Binding command names cannot contain =; use command-source for assignments"))
        (tmux-command-text arguments))))

(in-package #:libtmux)

(defun list-commands (client &key command format cancel-token timeout output-limit)
  "Inspect built-in tmux commands; return owned UTF-8 printer text and an outcome.
Omit COMMAND to list all built-ins. COMMAND is an exact name or built-in alias
through tmux 3.5a; unknown selectors produce no rows. From 3.6, unique prefixes
are accepted and unknown/ambiguous selectors fail. Configured command-alias
entries are not listed or expanded by this selector.

FORMAT is explicit tmux format source, without time expansion. #() can start
asynchronous jobs owned by this command client; results may be incomplete and
disconnect cleans up those jobs. Omission uses tmux's human-readable format.
Preserve native escaping, whitespace and after-hook output; this is not a
decoded registry.
Blocks under shared preflight/dispatch limits, never retries and starts no
daemon. Failures retain their outcome; invalid UTF-8 signals DECODING-ERROR.
See also: LIST-KEYS, DISPLAY-MESSAGE, OUTCOME-STDOUT, ERROR-OUTCOME."
  (libtmux.internal::printed-command
   client (append '("list-commands")
                  (when format (list "-F" (libtmux.internal::text-argument format "Command format")))
                  (when command
                    (list "--" (libtmux.internal::text-argument command "Command selector" nil))))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun list-keys (client &key table key format cancel-token timeout output-limit)
  "Inspect key bindings; return owned UTF-8 printer text and a command outcome.
Omit TABLE to list every key table. TABLE and KEY are literal strings; native
unknown-table and invalid-key failures remain errors. An unbound valid KEY is
an error except on tmux 3.7 through 3.7c, which return empty text. Those releases
also send a single matching row to the server message log and any selected
frontend's status line instead of stdout. Empty text does not prove absence.
FORMAT is explicit tmux format source
and requires live tmux 3.7 or newer; older daemons signal UNSUPPORTED-CAPABILITY
before payload dispatch. Omission uses the native human-readable listing.

FORMAT has no time expansion. #() can start asynchronous command-client jobs,
whose output may be incomplete and whose cleanup follows client disconnect.
Empty expanded lines may be omitted. Native escaping, whitespace and after-hook
output are preserved; the text is not a parsed or replayable configuration.
Blocks under shared preflight/dispatch limits and never retries. Invalid UTF-8 signals
DECODING-ERROR; operational failures retain their outcome.
See also: BIND-KEY, UNBIND-KEY, LIST-COMMANDS, ERROR-OUTCOME."
  (libtmux.internal::printed-command
   client (append '("list-keys")
                  (when table (list "-T" (libtmux.internal::text-argument table "Key table" nil)))
                  (when format (list "-F" (libtmux.internal::text-argument format "Key format")))
                  (when key (list "--" (libtmux.internal::text-argument key "Key" nil))))
   :minimum-version (when format "3.7") :feature :key-listing-format
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun bind-key (client key &key (table "prefix") repeat note
                               (command nil command-p) (command-source nil source-p)
                               cancel-token timeout output-limit)
  "Replace TABLE's KEY binding and return a COMMAND-OUTCOME.
TABLE defaults to prefix. KEY, TABLE and optional NOTE are literal strings.
REPEAT enables native key repetition. Supply exactly one of COMMAND argv or
COMMAND-SOURCE, explicit tmux parser source. COMMAND argv owns each argument
and preserves its token boundary; its first token must not contain =.

Tmux parses the binding immediately. Assignments/directives in COMMAND-SOURCE
can change daemon environment before a later parse error. Aliases expand during
binding in both forms and can also introduce parser side effects. Failure is
not rollback. Ordinary stored command nodes run later on a key event with its
native target context; this does not retain captured-handle authority.

Success acknowledges the binding and its hooks, not later key execution.
Blocks under shared preflight/dispatch limits, acquires no observation and
never retries. Native key/source errors and uncertain outcomes remain inspectable.
See also: UNBIND-KEY, LIST-KEYS, SEND-KEYS, ERROR-OUTCOME."
  (libtmux.internal::perform-command
   client nil
   (append (list "bind-key" "-T" (libtmux.internal::text-argument table "Key table" nil))
           (when repeat '("-r"))
           (when note (list "-N" (libtmux.internal::text-argument note "Binding note")))
           (list "--" (libtmux.internal::text-argument key "Key" nil)
                 (libtmux.internal::binding-command-source command command-p command-source source-p)))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))

(defun unbind-key (client key &key (table "prefix") cancel-token timeout output-limit)
  "Remove exactly one KEY from TABLE and return a COMMAND-OUTCOME.
TABLE defaults to prefix. Both strings are literal. A missing key in an
existing table is a native no-op; an absent table is an error. Removing its last
binding can delete the table, so repeated removal need not succeed. No bulk
deletion, reset or retry is implicit. Blocks under shared preflight/dispatch
limits. Success acknowledges removal and hooks; it cannot undo earlier key
execution. Native errors and uncertain outcomes retain their diagnostics.
See also: BIND-KEY, LIST-KEYS, ERROR-OUTCOME."
  (libtmux.internal::perform-command
   client nil (list "unbind-key" "-T" (libtmux.internal::text-argument table "Key table" nil)
                    "--" (libtmux.internal::text-argument key "Key" nil))
   :cancel-token cancel-token :timeout timeout :output-limit output-limit))
