# Explicit operations

Named operations take the connection client first and a captured target where
needed.

- They read current state to validate the target, then use its identity.
- Earlier captures stay unchanged.
- Every operation accepts `:cancel-token`, `:timeout` and `:output-limit`. The
  latter two default to the client settings and cover validation, dispatch and
  any follow-up acquisition together.
- All operations need a live daemon. `new-session` creates a session there.
  Daemon startup is separate; see [managed daemon scopes](daemons.md).
- No operation retries an uncertain mutation.

| Operation | Target / result |
| --- | --- |
| `rename-window`, `rename-session` | Physical entity; command outcome with optional replacement |
| `select-window` | Window link, preserving session/index context |
| `select-pane` | Physical pane |
| `next-window`, `previous-window`, `last-window` | Session; outcome containing its selected window link |
| `last-pane` | Physical window; outcome containing its selected pane |
| `new-session` | Selected live daemon; outcome containing the created session |
| `new-window` | Captured session; outcome containing the physical window |
| `split-pane` | Captured pane; outcome containing the new pane |
| `capture-pane` | Pane; UTF-8 text and diagnostic outcome as two values |
| `capture-pane-bytes` | Pane; owned octets and diagnostic outcome as two values |
| `send-text`, `send-keys`, `send-prefix` | Pane; command outcome for the send request |
| `respawn-pane`, `respawn-window` | Physical target; explicit process replacement and optional captured result |
| `pipe-pane` | Pane; explicit shell source, direction and daemon-owned pipe |
| [`switch-client`](api.md#switch-client-function) | Captured terminal client and destination session; outcome with optional replacement |
| [`detach-client`](api.md#detach-client-function), [`refresh-client`](api.md#refresh-client-function), [`suspend-client`](api.md#suspend-client-function), [`lock-client`](api.md#lock-client-function) | Captured terminal client; outcome acknowledging the request |
| [`lock-session`](api.md#lock-session-function), [`lock-server`](api.md#lock-server-function) | Frontends attached to a captured session or the addressed daemon; request outcome |
| [`wait-for`](api.md#wait-for-function) | Literal server channel; signal, wait, lock or unlock outcome |
| `clear-history`, `copy-mode` | Pane; command outcome |
| `resize-pane`, `resize-window` | Physical target; outcome with optional replacement |
| `select-layout`, `next-layout`, `previous-layout` | Physical window; outcome with optional replacement |
| `link-window`, `move-window`, `break-pane` | Explicit link/session/index context; outcome containing the destination link |
| `swap-windows`, `swap-panes` | Two targets; outcome containing a fresh vector in argument order |
| `unlink-window` | Window link; outcome without a replacement |
| `move-pane`, `join-pane`, `rotate-window` | Physical targets; outcome with optional replacement |
| `list-buffers` | Fresh vector of metadata plists and diagnostic outcome |
| `show-buffer` | Owned octets and diagnostic outcome |
| `set-buffer`, `load-buffer`, `save-buffer`, `delete-buffer`, `paste-buffer` | Explicit buffer data/path/name and optional pane; command outcome |
| [`set-option`](api.md#set-option-function), [`unset-option`](api.md#unset-option-function) | Typed live-catalog option mutation in one explicit table |
| [`set-hook`](api.md#set-hook-function), [`unset-hook`](api.md#unset-hook-function) | Tmux command-source installation/removal; never evaluates source as Lisp |
| [`set-environment`](api.md#set-environment-function), [`unset-environment`](api.md#unset-environment-function), [`remove-environment`](api.md#remove-environment-function) | Raw global/session environment value, deletion or tombstone |
| [`kill-pane`](api.md#kill-pane-function), [`kill-window`](api.md#kill-window-function), [`kill-session`](api.md#kill-session-function) | Exact captured entity; outcome without replacement |
| [`kill-server`](api.md#kill-server-function) | Retained live daemon; proven process exit or uncertain outcome |

- Creation defaults to detached mode. Selection uses explicit captured targets.
- `new-window :index` chooses a free session index.
- `split-pane` takes `:horizontal` (left/right) or `:vertical` (top/bottom),
  with a cell `:size` or `:percent`.
- Creation returns a fresh captured entity through `outcome-value`.
- Typed option/hook values, inherited table reads and environment presence:
  see [decoded configuration](configuration.md). Raw printers stay available
  for unrestricted native inspection.

## Names and child commands

Names and creation `:cwd` strings:

- Literal, including `#[...]` and `#{...}` text. Rename's `:format-p t`
  requests tmux format expansion.
- tmux can normalize or reject a name. The replacement observation holds the
  result.
- `:cwd` follows tmux's relative-path rules. tmux can fall back from an
  inaccessible cwd, so check from the child side when the exact directory
  matters.

Creation commands:

- `:command` is a nonempty list/vector of argv strings. `:shell-command` is a
  single string. Omit both for tmux's default shell. An empty argv is invalid.
- Strings may contain spaces, quotes, semicolons, dollar signs, backslashes and
  Unicode. The encoder preserves argument boundaries.
- A one-element argv starts that executable with no added argument.
- `:environment` is a list/vector of `(name . value)` string pairs.

Size limit:

- The final encoded tmux command is limited to 16,000 UTF-8 bytes, counting
  the NUL between argv entries. Nested command quoting counts too.
- Oversized named commands fail before their payload is dispatched. They are
  never split into several mutations.

## Terminal input

- `send-text` sends literal text (`C-c` arrives as characters). `:enter t`
  appends one Return in the same request.
- `send-keys` takes a nonempty list/vector of tmux key strings and a positive
  `:repeat`. tmux recognizes names such as `C-c` and `Enter`, and falls back to
  literal input for other strings.
- `send-prefix` uses the configured prefix. `:second t` selects prefix2.
- The pane's current tmux mode handles input.
- Success means tmux processed the request, not that the application consumed
  it. Coordinate dependent work through an application signal.

`copy-mode` and `clear-history`:

- `copy-mode` enters copy mode. `:page-up t` scrolls on entry; `:exit t`
  exits. The two are mutually exclusive.
- `clear-history` removes retained tmux history. It does not promise to clear
  the application's current screen.

## Geometry and selection

Resize:

- `resize-pane` and `resize-window` take positive cell `:width`/`:height`, or
  a `:direction` (`:left`, `:right`, `:up`, `:down`) with a positive `:amount`
  (default 1).
- Absolute dimensions run from 1 to 10,000. Relative amounts run from 1 to
  2,147,483,647.
- tmux may clamp the layout. The replacement observation holds the resulting
  dimensions.
- Pane `:zoom t` toggles zoom. Window `:fit :smallest` or `:fit :largest`
  fits the attached clients. Neither combines with dimensions or direction.
- A window resize sets tmux's `window-size` option to manual.

Layout:

- `select-layout` takes `:even-horizontal`, `:even-vertical`,
  `:main-horizontal`, `:main-vertical`, `:tiled`, or
  `(:custom "tmux-layout-description")`.
- tmux validates custom checksums and geometry.
- Layout operations unzoom the window. `next-layout` and `previous-layout`
  follow tmux's layout ordering.

Selection:

- `next-window`, `previous-window` and `last-window` take a captured session
  and return its newly observed active **window link** through
  `outcome-value`.
- Next and previous accept `:activity t` to restrict selection to alerting
  windows.
- `last-pane` takes a physical window and returns its observed active pane.
  tmux signals when no last selection exists.
- These operations and geometry accept `:observe nil` to skip follow-up
  acquisition.

## Attached terminal clients

[Fetch-clients](api.md#fetch-clients-function) returns attached-client
observations. They are distinct from the library connection passed as the first
argument.

- The five client operations in the table need an ordinary terminal client
  captured through that connection. Control-mode observations are rejected.
- Preflight requires one matching name and the same PID, creation time and tty.
  It rejects a name that matches another client's full or abbreviated tty.
- A missing, replaced or foreign observation signals
  [stale-target](api.md#stale-target-type).
- tmux has no dispatch-side client fingerprint guard across the supported
  floor, so a replacement between preflight and dispatch remains possible.

`switch-client`:

- Takes an explicit destination session and preserves that session's
  environment by default.
- `:update-environment t` applies tmux's `update-environment` option using the
  attached client's environment.
- Default `:observe t` acquires a replacement client observation. `:observe nil`
  skips that read. The earlier observation still points to its captured
  session.

The other four:

- `refresh-client` schedules a full redraw. `:status-only t` redraws only the
  status line. [Refresh](api.md#refresh-function) instead acquires a
  replacement observation.
- `detach-client` requests detachment of the selected client.
- `suspend-client` requests native SIGTSTP suspension. The controlling
  application owns resumption.
- `lock-client` asks the frontend to run its configured `lock-command` through
  a shell.
- An already suspended client can turn suspend or lock into a no-op. tmux also
  ignores an empty or oversized lock command.
- These four return no replacement observation.

Success acknowledges the server's request.

- It does not prove frontend exit, terminal restoration, completed redraw,
  suspension, lock startup or authentication. Coordinate dependent work
  through the frontend's own completion signal.
- Missing dispatch or completion evidence is an unknown outcome.

[`lock-session`](api.md#lock-session-function) requests locking for frontends
attached to the selected session when tmux executes the command.
[`lock-server`](api.md#lock-server-function) requests it across the addressed
daemon.

- Both use live membership, including frontends attached after the caller's
  capture.
- They return one request outcome, with no per-frontend results.
- Control clients, already suspended frontends and empty or oversized lock
  commands are skipped. No eligible frontend is a successful no-op.
- They run the configured frontend lock programs. They do not block other tmux
  commands or suspend pane processes.
- Closing the library client leaves the frontend programs running.
- Hooks can add effects or fail after the requests were sent, so a failed
  outcome does not undo a lock request.
- See tmux's
  [`server_lock`](https://github.com/tmux/tmux/blob/3.8/server-fn.c#L175-L218).

## Message printing

[`display-message`](api.md#display-message-function) returns two values: owned
strict UTF-8 text and its diagnostic command outcome.

- It uses tmux's ordinary `-p` printer and preserves whitespace, including the
  final newline.
- Message text is literal by default, including `#{...}`, `#(...)`, `#[...]`
  and `%Y`.
- Literal input disables expansion. It does not make the printer a
  byte-identical echo: native versions can escape output, such as `$` on tmux
  3.4. The API keeps that presentation and does not decode it as field data.
- Invalid UTF-8 raises [`decoding-error`](api.md#decoding-error-type) with the
  outcome's original bytes.

`:target`:

- Accepts a captured session, physical window, pane or window link owned by
  the supplied client.
- Use a link when its session and index matter. A physical window or pane lets
  tmux choose its session context. Omitting the target lets tmux choose the
  whole context.
- Authority and stale-link checks run before the request. No replacement is
  acquired.

`:format-p t` enables tmux format and time expansion.

- A `#()` expression may start a shell job, but expansion does not wait for
  its result. A fresh command client may print an empty or incomplete result.
- The native command client owns those jobs and cleans them up on disconnect.
  The API offers no job completion or background process ownership.

After-hooks can print extra text or have effects.

- The returned text keeps that output. It does not establish one field's value
  or presence. Use captured getters for local field reads.
- Decoded configuration acquisition is a separate capability.

Version differences:

- tmux 3.4 or newer prints literal text natively.
- The 3.3a fallback escapes format and time syntax and limits the intermediate
  after time expansion to 8,191 UTF-8 bytes. The check runs after live-version
  preflight and before payload dispatch. The encoded command limit also
  applies.
- See
  [`cmd_display_message_exec`](https://github.com/tmux/tmux/blob/3.8/cmd-display-message.c#L62-L176).

## Commands and key bindings

[`list-commands`](api.md#list-commands-function) and
[`list-keys`](api.md#list-keys-function) return ordinary UTF-8 printer text and
the retained outcome.

- Both keep native escaping, whitespace and after-hook output.
- Use them for inspection, not replay or decoded configuration lookup.

`list-commands`:

- Lists built-ins. Optional `:command` takes exact names or built-in aliases.
  Configured `command-alias` entries are not in that table.
- Before tmux 3.6, an unknown selector produces no rows. From 3.6, unique
  prefixes work, and unknown or ambiguous selectors fail.

`list-keys`:

- Takes an optional literal `:table` and `:key`. Omitting the table means all
  tables.
- Unknown tables and invalid key syntax are errors.
- A valid but unbound key is an error, except on tmux 3.7 releases, which
  return empty text.
- Those 3.7 releases also send a single matching row to the server message log
  and any selected frontend's status line instead of stdout, even with
  `:format`. Multiple matching rows print normally.
- So empty text does not show a binding is absent, and inspection can display
  a status message. The native
  [single-row branch](https://github.com/tmux/tmux/blob/3.7c/cmd-list-keys.c#L236-L248)
  changes in [tmux 3.8](https://github.com/tmux/tmux/blob/3.8/cmd-list-keys.c#L220-L248).

`:format` on both:

- `list-keys :format` needs tmux 3.7 or newer. Older daemons reject it before
  payload dispatch.
- Both listing functions take explicit tmux format source without time
  expansion, so `%Y` stays literal. Empty formatted rows may be omitted.
- Format jobs have the same asynchronous lifetime limits as message printing.

[`bind-key`](api.md#bind-key-function) replaces one binding in `:table`
(default `"prefix"`).

- Supply exactly one of `:command` argv or `:command-source` (explicit tmux
  source).
- The argv form preserves token boundaries and rejects `=` in its command-name
  token.
- `:note` is literal text. `:repeat t` enables native repetition.
- The stored command nodes run when tmux dispatches that key, in the key
  event's context. A captured target's authority does not carry into future
  execution.

tmux parses binding source immediately.

- Assignments and directives can alter the daemon's environment before a later
  parse error.
- Aliases resolve during binding and can cause parser effects even through
  argv.
- A failed bind is not a rollback. Missing completion evidence can leave the
  outcome unknown.
- Keep source and aliases under the application's control.
- See tmux's
  [`cmd_bind_key_exec`](https://github.com/tmux/tmux/blob/3.8/cmd-bind-key.c#L55-L107)
  and [assignment grammar](https://github.com/tmux/tmux/blob/3.8/cmd-parse.y#L224-L244).

[`unbind-key`](api.md#unbind-key-function) removes exactly one key, also from
`"prefix"` by default.

- A missing key in an existing table is a no-op. An absent table is an error.
- Removing a table's last binding may delete the table, so a second removal
  need not succeed.
- Neither helper retries or removes all bindings.
- Binding success acknowledges storage and hooks, not later key execution.
  [`send-keys`](api.md#send-keys-function) sends pane input and does not
  exercise a frontend's key-binding dispatch.

## Server access

[`server-access`](api.md#server-access-function) takes a literal account name
and one operation:

- `:allow` adds a writable entry. `:deny` removes one.
- `:read-only` and `:read-write` update or add an entry.
- Duplicate additions and missing removals are errors.
- tmux resolves names through the daemon's name service. Strings are not
  numeric UIDs.
- Root and the daemon-owner UID cannot be changed.
- `:group-p t` selects a group name. It needs live tmux 3.8; older daemons
  reject it before payload dispatch.

Access rules:

- Removal does not create a deny rule. From tmux 3.8, a user without an
  explicit entry can still match its connecting peer's GID.
- An explicit UID entry wins over the GID entry. Supplementary groups are not
  searched.
- Configure socket and directory access separately. An ACL entry alone does
  not make the endpoint reachable.

Connected clients:

- In tmux 3.8, removal and read-only/read-write updates recompute every
  client's effective ACL. A writable entry can clear an unrelated frontend's
  separately set read-only flag.
- A request can schedule disconnection without proving frontend exit. A later
  grant does not cancel an already scheduled exit.
- `:allow` alone does not recompute connected-client flags.
- Earlier captures keep their values. Use [`refresh`](api.md#refresh-function)
  for a replacement observation.
- See the native [command](https://github.com/tmux/tmux/blob/3.8/cmd-server-access.c#L61-L152)
  and [ACL update](https://github.com/tmux/tmux/blob/3.8/server-acl.c#L71-L110).

[`list-server-access`](api.md#list-server-access-function) returns ordinary
UTF-8 listing text and an outcome.

- Rows use `(R)`/`(W)` before tmux 3.8 and add `U`/`G` account kinds from 3.8.
- UID 0 is omitted. A failed name lookup prints `unknown`.
- Empty text does not show that nobody has access.
- It is for inspection, not a decoded authorization model.

Cross-user connection, authorization and revocation behavior is untested.
Tests use private sockets under one OS user.

## Wait channels

[`wait-for`](api.md#wait-for-function) takes `:operation :wait` (default),
`:signal`, `:lock` or `:unlock`, and a nonempty literal channel name.

- Signal and unlock work on the supported tmux floor.
- Wait and lock need tmux 3.8's client-loss cleanup. Older daemons signal
  [`unsupported-capability`](api.md#unsupported-capability-type) before
  dispatch. This restricts one capability, not the core tmux floor.

Signals:

- A signal wakes existing waiters.
- With none waiting, one signal leaves a pending wake. A second can remove it.
- It is neither an idempotent latch nor a counting semaphore. Use an
  application protocol when acknowledgements or sender identity matter.
- Server shutdown can flush waiting requests.

Locks:

- A lock belongs to the daemon channel, not to a Lisp client or thread.
- It survives a completed call and client closure for the daemon's lifetime.
- Unlock explicitly. No resource macro or automatic cleanup unlocks.
- Signals and locks share native channel state. Use different channel names
  for each protocol.

Blocking and cancellation:

- Each call blocks its caller. Use a second connection client to signal or
  unlock another client's pending operation.
- Timeout and byte limits include preflight.
- Cancellation removes the owned command process. tmux 3.8 removes a
  disconnected queued waiter.
- Cancellation or lost receipts cannot prove a signal was not consumed or a
  lock was not granted. Inspect the retained outcome and recover through the
  application.
- See [`cmd_wait_for_client_lost`](https://github.com/tmux/tmux/blob/3.8/cmd-wait-for.c#L483-L515).

## Links and pane placement

Window links:

- `link-window` and `move-window` take a source **window link**, a destination
  session and an explicit free index. The source link preserves session group
  context. Neither overwrites an occupied index.
- Moving removes only the selected source link. Removing a session's last link
  can destroy that session.
- `unlink-window` refuses a last reference unless `:kill-if-last t`. tmux
  session groups affect its last-reference check.
- `swap-windows` takes two links and returns their replacement links in
  argument order. `:select t` selects the affected indexes; omit it to keep
  the current indexes.
- An old link whose index now points at another window is stale.

Panes:

- `move-pane` and `join-pane` take source and destination physical panes.
  `:direction`, `:size`, `:percent`, `:before` and `:full-size` control
  placement. `:detached t` is the default.
- An emptied source window and all its links are destroyed.
- With `:detached nil`, tmux chooses the session context of the physical
  destination.
- Percentage sizing follows the installed tmux. With `:full-size t`, 3.3a uses
  the destination pane's dimensions and 3.8 uses the whole window. Use `:size`
  for cell-based control.
- `swap-panes` preserves physical IDs and returns replacements in argument
  order.
- `rotate-window` moves pane positions `:up` (default) or `:down` and advances
  the active pane. Both accept `:preserve-zoom t`.
- Placement operations preserve older observations. A successful operation may
  have a separate observation failure. Unlink has no replacement to observe.

`break-pane` takes the pane, its explicit source link, a destination session
and a free index.

- The source link matters when the pane is its window's only pane: tmux moves
  that link and keeps the other links and the physical window.
- The outcome contains the destination link. Optional `:name` is literal.
- tmux 3.7 has an inverted new-window naming branch, fixed in 3.7a. The
  library picks the safe branch from the live pane count inside the guarded
  request.
- For a new window with an explicit name, it follows the break with
  `rename-window` on the moved pane. That adds no subprocess or retry, but it
  can run an `after-rename-window` hook and is not transactional: a failing
  hook can leave the pane moved and renamed. Inspect the retained command
  outcome before deciding what to do.
- Unnamed single-pane moves keep their existing name and automatic-rename
  setting.
- See [`cmd_break_pane_exec` in 3.7](https://github.com/tmux/tmux/blob/3.7/cmd-break-pane.c#L116-L123)
  and [the corrected 3.7a branch](https://github.com/tmux/tmux/blob/3.7a/cmd-break-pane.c#L116-L123).

## Pane processes

Respawn:

- `respawn-pane` restarts its process. `respawn-window` restarts the physical
  window as one pane: it keeps the first pane and destroys every other pane,
  including through other session links.
- Neither kills a running process unless `:kill t`.
- Omit `:command` and `:shell-command` to reuse the stored command. Explicit
  argv, shell text, cwd and environment follow creation.
- By default `outcome-value` supplies a new observation. Earlier captures stay
  unchanged.
- A fast-exiting process can disappear before acquisition.

`pipe-pane` takes an explicit `:shell-command`.

- `#` and `%` stay literal by default. `:format-p t` enables tmux format and
  time expansion before the shell runs.
- A literal command must fit tmux's 8,191-byte time-format capacity after
  format escaping.
- `:direction` is `:output` (pane to shell), `:input` (shell to pane) or
  `:both`.
- Omit the command to close the pipe. `:toggle t` closes an existing pipe
  without starting its replacement.
- Success acknowledges configuration. It does not show shell startup, command
  success or data consumption. Coordinate dependent work through an
  application signal.
- tmux owns the pipe child. Closing the library client leaves it running.
- Replacing or explicitly closing the pipe releases the pane's connection to
  that child.

## Buffers

`list-buffers` returns a fresh vector of plists with `:buffer/name`,
`:buffer/size` (bytes) and `:buffer/created` (Unix seconds).

- It keeps tmux's listing order, decodes at most 10,000 rows by default, and
  returns `#()` when empty.
- Names are mutable locators, not captured entity identities.

`set-buffer` and `show-buffer`:

- `set-buffer` takes a literal NUL-free string or an octet vector. Octets go
  through tmux's stdin buffer loader, keeping NUL and invalid UTF-8.
  `:append t` works for strings.
- `show-buffer` returns owned octets without decoding.
- Both take a literal `:name`. Setting without a name creates an automatic
  buffer.
- Creation through set/load rejects backslashes, ASCII controls and DEL before
  I/O, because tmux versions otherwise rewrite or reject them. Spaces and
  Unicode work.
- Looking up an existing buffer keeps its actual name.

`show-buffer` runs one ordinary unattached tmux client with stdout reserved for
buffer bytes.

- The same live server guard, operation budget and alias audit apply.
- It succeeds only after normal process completion and complete pipe draining,
  with exit zero and empty stderr. A hook cannot hide an error by changing the
  exit status.
- A read failure after launch retains partial output and diagnostics. It does
  not show the read was never dispatched.
- Buffer contents are never parsed as receipts or errors. Control mode is not
  covered.

`load-buffer` and `save-buffer`:

- Take literal file-path strings. `:name` selects the buffer.
- Save overwrites unless `:append t`.
- Relative paths follow the tmux command client's cwd.
- A literal file named `-` must be spelled `./-`. Use set/show for in-memory
  bytes.
- Empty input or an empty loaded file is tmux's no-op and keeps any existing
  buffer.
- Save success records tmux's reported completion. It does not verify file
  contents or durability. tmux 3.3a can suppress some file-write errors.

`paste-buffer` takes a physical pane and optional `:name`.

- Newlines become Return by default. `:raw t` keeps them. A `:separator`
  string replaces each newline.
- `:bracketed t` requests bracket markers when the pane enabled bracketed
  paste.
- `:verbatim t` keeps all bytes and disables newer tmux control-byte
  sanitization. It cannot add separators or bracket markers.
- Flags come from the live daemon version.
- `:delete t` removes the buffer after pasting.
- Input disablement and application consumption are outside the library.

`delete-buffer :name` needs tmux 3.4 or newer.

- On 3.3a it signals `unsupported-capability` before dispatch, because that
  release can delete an unrelated top buffer when the named buffer is missing.
- The condition exposes `error-feature`, `error-required-version` and
  `error-actual-version`. The check uses the live daemon's version, not the
  selected executable's.

Omitting a buffer name for show, save, paste or delete uses tmux's default:
the newest buffer on 3.3a, and the newest **automatic** buffer from 3.4 onward.
On modern tmux it never selects the newest explicitly named buffer.

## Configuration inspection

[`show-options-text`](api.md#show-options-text-function),
[`show-hooks-text`](api.md#show-hooks-text-function) and
[`show-environment-text`](api.md#show-environment-text-function) return native
UTF-8 printer text and a retained command outcome.

- Supply an explicit scope. Local tables need the matching captured target.
- Normal client identity, preflight, last-moment target guards, cancellation
  and resource limits apply.
- They acquire state and do not change earlier observations.

This function from the [example package](../examples/workspace.lisp) returns
three printer views plus their diagnostic outcomes. The
[REPL tutorial](tutorial.md) supplies the package's `tm` nickname and setup.

<!-- example:configuration -->
```lisp
(defun configuration-report (client session)
  "Read native configuration text; return an owned report and diagnostic outcomes."
  (let ((outcomes nil))
    (flet ((inspect-text (reader &rest options)
             (multiple-value-bind (text outcome) (apply reader client options)
               (push outcome outcomes)
               text)))
      (let ((report
              (list :options (inspect-text #'tm:show-options-text
                                           :scope :session :target session
                                           :name "status" :include-inherited t)
                    :hooks (inspect-text #'tm:show-hooks-text
                                         :scope :session :target session)
                    :environment (inspect-text #'tm:show-environment-text
                                               :scope :session :target session))))
        (values report (coerce (nreverse outcomes) 'simple-vector))))))
```
<!-- /example -->

Options and hooks:

- `:name` is a literal tmux reference. Format-looking characters stay literal;
  native abbreviations and array-reference syntax still apply. Omit it to list
  the table.
- `:scope` selects native flags. tmux can infer a built-in option's table from
  its name.
- These raw inspectors do not enforce the typed mutation catalog's name/type
  restrictions.
- A physical window's native format context need not identify one captured
  session link. Use a session target for session-table inspection.
- `show-options-text` exposes `:include-inherited` (`-A`), `:include-hooks`
  (`-H`) and `:value-only` (`-v`). Native whole-table `-A` output does not
  promise inherited user `@` options.
- `show-hooks-text` has no server-scope flag. Its named printer can return an
  ordinary `@` option without proving event registration. `:monitors` selects
  native monitor presentation.
- Both printers' `:format` and hook monitor inspection need live tmux 3.8.
  Format text is explicit tmux source with no implicit time expansion. `#()`
  can start command-client jobs whose results may be incomplete and whose
  cleanup follows client disconnect.

Environment:

- Scopes are `:global` and captured `:session`. Session output is the raw
  table, not a merged child environment.
- `:hidden t` selects hidden entries. The default selects ordinary entries. A
  visibility mismatch may succeed with empty text, which does not show
  absence.
- `:shell-format t` returns native shell-looking text as data. No reader
  executes it.
- Names may contain spaces, format punctuation and Unicode. Only empty text,
  NUL and `=` are rejected.

Text limits:

- Escaping, whitespace and ordinary hook output stay in the returned
  presentation. Foreign names and multiline values can make bulk text
  ambiguous.
- Missing names remain native errors with outcome evidence. Invalid UTF-8
  signals a decoding condition that retains the client and original bytes.
- No parsed values, presence, inherited provenance or complete decoded
  records. For those, use [decoded configuration](configuration.md).

## Configuration mutations

[`set-option`](api.md#set-option-function) and
[`unset-option`](api.md#unset-option-function) address one explicit tmux option
table.

- Server and global scopes reject a target. Session, window and pane scopes
  need a captured target of that type, so the normal generation and
  last-moment target guards apply.
- The exact live daemon version selects the reviewed option catalog after
  preflight. The executable's version cannot substitute for it.
- The catalogs cover tmux 3.3a through 3.8. An unreviewed neighboring release
  signals an error; see [capabilities and current limits](capabilities.md).

Literal writes:

- They validate the catalog's native Boolean, integer, choice and text type
  before payload dispatch. `nil` is a valid false value and becomes tmux
  `off`.
- `:format-p t` instead accepts explicit tmux format text and lets the daemon
  validate the expanded value.
- Registered array elements use `:key` and never allocate a vector by the
  greatest numeric key.
- Without `:key`, an array value uses the option's native tmux list grammar and
  may create several entries. Use `:key` to keep one literal entry.
- `:append t` is accepted only where tmux implements it: strings, keyed
  string-array values and unkeyed array assignment.
- Public user-option writes accept the reversible `@[A-Za-z0-9_.-]+` name
  grammar.

`:only-if-unset t` requests a local absent-only write.

- An inherited value permits a local override.
- An existing local value, including false or empty text, refuses replacement
  and retains the normal condition/outcome evidence.
- With `:key`, tmux tests that array element; other local keys may already
  exist. Without a key, it tests the local option entry.
- The condition applies once, to the selected command. Hooks and later
  operations are independent.
- The default keeps ordinary replacement.

[`set-hook`](api.md#set-hook-function) takes explicit tmux command source. It
does not parse the source as Lisp or run it locally.

- Ordinary installation never uses tmux's immediate-run flag. tmux can still
  run a registered native after-hook such as `after-set-hook` while processing
  the command.
- Keyed hook entries do not support appending command text. Unkeyed append adds
  hook entries through tmux's array grammar.
- [`unset-hook`](api.md#unset-hook-function) removes the hook.
- Registered hooks stay separate from ordinary option writes. The live catalog
  gates dynamic event sources.

[`set-environment`](api.md#set-environment-function) writes one raw global or
captured-session environment table.

- Literal text by default. `:format-p t` requests format expansion. It also
  takes tmux's hidden flag.
- [`unset-environment`](api.md#unset-environment-function) deletes an entry.
  [`remove-environment`](api.md#remove-environment-function) stores tmux's
  removal marker. A tombstone, absence and a present empty string stay
  distinct.
- Names use `[A-Za-z_][A-Za-z0-9_]*` so later named acquisition is reversible.

All seven operations:

- Return a [`command-outcome`](api.md#command-outcome-type) that retains
  effective arguments and diagnostics.
- For native printer views, use the guarded
  [text inspectors](#configuration-inspection). For typed, presence-aware reads, use
  [decoded configuration](configuration.md).
- Use [`run-command`](api.md#run-command-function) when raw tmux argv and its
  weaker target contract are intentional.

## Explicit termination

[`kill-pane`](api.md#kill-pane-function),
[`kill-window`](api.md#kill-window-function) and
[`kill-session`](api.md#kill-session-function) take one captured physical
target.

- The same preflight and last-moment guards as other named mutations reject a
  missing, replaced or foreign-generation target.
- They do not expose tmux's broad `-a` forms.
- Killing a physical window removes all its links. Killing a session removes
  that session's links and any now-unreferenced panes.

[`kill-server`](api.md#kill-server-function) is separate from
[`close-client`](api.md#close-client-function). Closing releases library-owned
resources and leaves tmux alive.

- Server termination succeeds only when a pre-dispatch receipt and readiness
  of the pidfd retained for the daemon accepted during this call's preflight
  prove both dispatch and process exit.
- Daemon death without the receipt stays `:unknown`, because another actor
  could have terminated it.
- After observed death the client stays open but its generation is
  invalidated. Retained captures still support local traversal and projection.

All four operations are destructive.

- Select the target once and establish cardinality before dispatch.
- When completion is uncertain, inspect the retained condition outcome.

## Outcomes and target checks

Mutators return `command-outcome`. `outcome-value` returns a value and presence
as two values.

- Rename and selection accept `:observe nil` to skip follow-up acquisition.
- Otherwise a successful mutation followed by a failed acquisition still has
  status `:succeeded`, no value, and an `outcome-observation-error`.

| Evidence | Outcome |
| --- | --- |
| Preflight failed or live guard explicitly rejected the target | `:not-dispatched` |
| Completion receipt, successful tmux process exit and empty stderr | `:succeeded` |
| Completion receipt and nonzero process exit | `:failed` |
| Successful process exit with diagnostic output | `:unknown` |
| Dispatched operation lacks required receipts, or transport lost completion | `:unknown` |
| Server pidfd proves exit but the pre-dispatch receipt is missing | `:unknown` |
| Server receipt and retained pidfd both prove explicit termination | `:succeeded`, phase `:server-terminated` |
| Server exit wait fails after dispatch | `:unknown`, reason `:server-exit-unobserved`; cause retained |

- The outcome retains exit status, diagnostic bytes, effective arguments and
  elapsed time.
- A failed command queue can have completed effects. There is no rollback.

Target checks:

- Validation checks the live server generation and captured entity identity.
- The dispatch connection checks the daemon again. Immediately before the
  payload it checks physical targets and session/index/window mappings. A
  reused link index signals `stale-target`.
- These checks do not make selection and mutation a transaction: tmux hooks
  and other clients can change state.

Capture:

- Preserves whitespace and trailing lines.
- The text API strictly decodes UTF-8. Decoding failures retain the client and
  raw command outcome. The byte API copies output without decoding.
- Flags expose tmux's history, wrapping, alternate-screen, pending-output and
  escape modes. They do not reconstruct terminal bytes tmux did not retain.

## Command aliases and daemon configuration

Named APIs need the original built-in command meanings and stable
`command-alias` configuration during each call.

- `show-options` is the trusted bootstrap spelling used to inspect aliases. It
  must remain the built-in command.
- The audit cannot safely inspect an arbitrary override of itself, and cannot
  prevent configuration changes after inspection.

Before acquisition or a named operation, the library reads `command-alias`.

- It signals `unsupported-configuration` for collisions with reserved command
  names. `error-setting` identifies the option; `error-commands` returns the
  colliding spellings.
- The reserved list is in [command-policy.lisp](../src/command-policy.lisp).
  Other alias names are allowed.
- The check conservatively rejects an apparent reserved assignment on any line
  of a multiline alias value.

Configured tmux hooks keep their ordinary behavior.

- The library does not remove aliases or hooks from the user's daemon.
- `run-command` remains the raw escape hatch: tmux's command grammar, no
  captured-target or alias audit.
