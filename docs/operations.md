# Explicit operations

Named operations take the connection client first and a captured target where
needed. They read current state to validate the target, then use its identity.
Earlier captures remain unchanged. Every operation accepts `:cancel-token`,
`:timeout` and `:output-limit`; the latter two default to the client settings
and cover validation, dispatch and any follow-up acquisition together.

The current APIs require a live daemon. `new-session` creates a session there;
daemon bootstrap is a separate unfinished part of the implementation.

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

Creation defaults to detached mode. Selection uses explicit captured targets.
`new-window :index` chooses a free session index. `split-pane` accepts
`:horizontal` (left/right) or `:vertical` (top/bottom), with a cell `:size` or
`:percent`. Creation returns a fresh captured entity through `outcome-value`.

## Names and child commands

Names and creation `:cwd` strings are literal. Rename's `:format-p t` explicitly
requests tmux format expansion. Tmux can normalize or reject a name; inspect the
replacement observation for the resulting name. Cwd text follows tmux's own
relative-path rules.

Creation accepts a nonempty `:command` list/vector of argv strings or a separate
`:shell-command` string. Omission selects tmux's default shell. Supplying an
empty argv is invalid. Strings may contain spaces, quotes, semicolons, dollar
signs, backslashes and Unicode; the encoder preserves their argument boundaries.
One-element argv starts that executable with no added program argument.
`:environment` is a list/vector of `(name . value)` string pairs.

The final encoded tmux command is limited to 16,000 UTF-8 bytes, including NUL
terminators between argv entries. Nested command quoting counts toward this
limit. Oversized named commands fail before their payload is dispatched. They
are never silently split into multiple mutations.

## Terminal input

`send-text` preserves literal text such as `C-c`; `:enter t` appends one Return
key in the same request. `send-keys` accepts a nonempty list/vector of tmux key
strings and a positive `:repeat` count. Tmux recognizes names such as `C-c` and
`Enter`, and falls back to literal input for unrecognized strings. `send-prefix`
uses the configured prefix; `:second t` selects prefix2.

The pane's current tmux mode handles input. Successful dispatch means tmux
processed the send request; it does not establish application consumption or
readiness. Coordinate dependent work through an application signal.

`copy-mode` enters copy mode; `:page-up t` scrolls on entry, and `:exit t` exits.
Page-up and exit are mutually exclusive. `clear-history` removes retained tmux
history; it does not promise to clear the application's current screen.

## Geometry and selection

`resize-pane` and `resize-window` accept positive cell `:width`/`:height`, or a
`:direction` (`:left`, `:right`, `:up`, `:down`) with positive `:amount` (default
one). Absolute dimensions range from 1 through 10,000, the common supported
range. Relative amounts range from 1 through 2,147,483,647. Tmux may clamp the
actual layout; the replacement observation contains the resulting dimensions.

Pane `:zoom t` toggles zoom. Window `:fit :smallest` or `:fit :largest` fits the
attached clients. These modes cannot be combined with dimensions or direction.
A window resize sets tmux's `window-size` option to manual.

`select-layout` accepts `:even-horizontal`, `:even-vertical`, `:main-horizontal`,
`:main-vertical`, `:tiled`, or `(:custom "tmux-layout-description")`.
Tmux validates custom checksums and geometry. Layout operations unzoom the
window. `next-layout` and `previous-layout` follow tmux's layout ordering.

`next-window`, `previous-window` and `last-window` take a captured session and
return its newly observed active **window link** through `outcome-value`.
Next and previous accept `:activity t` to restrict selection to alerting windows.
`last-pane` takes a physical window and returns its observed active pane.
Tmux signals when no last selection exists. These operations and geometry
accept `:observe nil` to omit follow-up acquisition.

## Attached terminal clients

[Fetch-clients](api.md#fetch-clients-function) returns attached-client observations;
they are distinct from the library connection passed as the first argument.
The five client operations above require an ordinary terminal client captured
through that connection. They reject control-mode observations. Preflight
requires one matching name and the same PID, creation time and tty. It also
rejects a name that matches another client's full or abbreviated tty. A missing,
replaced or foreign observation signals [stale-target](api.md#stale-target-type).
Tmux has no dispatch-side client fingerprint guard across the supported floor,
so replacement between preflight and dispatch remains possible.

`switch-client` takes an explicit destination session. It preserves that
session's environment by default; `:update-environment t` applies tmux's
`update-environment` option using the attached client's environment. Its default
`:observe t` acquires a replacement client observation; `:observe nil` omits
that read. The earlier observation still points to its captured session.

`refresh-client` schedules a full redraw; `:status-only t` schedules only the
status line. [Refresh](api.md#refresh-function) instead acquires a replacement
observation. `detach-client` requests detachment of the selected client.
`suspend-client` requests native SIGTSTP suspension; the controlling application
owns resumption. `lock-client` asks the frontend to execute its configured
`lock-command` through a shell. An already suspended client can make suspend
or lock a no-op; an empty or oversized lock command is also ignored by tmux.
These four calls return no replacement observation.

Success acknowledges the server's request. It does not prove frontend exit,
terminal restoration, completed redraw, process suspension, lock startup or
authentication. Coordinate dependent work through the frontend's own completion
signal. Missing dispatch/completion evidence remains an unknown outcome; the
library never retries these requests automatically.

## Wait channels

[`wait-for`](api.md#wait-for-function) accepts `:operation :wait` (the default),
`:signal`, `:lock` or `:unlock`, and a nonempty literal channel name. Signal and
unlock work on the supported tmux floor. Wait and lock require tmux 3.8's
client-loss cleanup; older daemons signal
[`unsupported-capability`](api.md#unsupported-capability-type) before dispatch.
This is a capability restriction, not a change to the core tmux floor.

A signal wakes existing waiters. With none waiting, one signal leaves a pending
wake; a second can remove it. This is neither an idempotent latch nor a counting
semaphore. Use an application protocol when acknowledgements or sender identity
matter. Server shutdown can also flush waiting requests.

Locks belong to the daemon channel, not a Lisp client or thread. They survive a
completed call and client closure within the daemon's lifetime. Unlock explicitly;
no resource macro or automatic cleanup unlocks them. Signals and locks share
native channel state, so use different channel names for those protocols.

Each call blocks its caller. Use a second connection client to signal or unlock
another client's pending operation. Timeout and byte limits include preflight.
Cancellation removes the owned command process; tmux 3.8 removes a disconnected
queued waiter. Cancellation or lost receipts cannot prove that a signal was not
consumed or a lock was not granted. Inspect the retained outcome and coordinate
recovery through the application; the library does not retry a channel request.
See [`cmd_wait_for_client_lost`](https://github.com/tmux/tmux/blob/3.8/cmd-wait-for.c#L483-L515).

## Links and pane placement

`link-window` and `move-window` take a source **window link**, a destination
session and an explicit free index. The source link preserves session group
context. Neither overwrites an occupied index. Moving removes only the selected
source link; removing a session's last link can destroy that session.
`unlink-window` refuses a last reference unless `:kill-if-last t` is explicit;
tmux session groups affect its last-reference check.

`swap-windows` takes two links and returns their replacement links in argument
order. `:select t` selects the affected indexes; omission retains current
indexes. An old link whose index now points at another window is stale.

`move-pane` and `join-pane` take source and destination physical panes.
`:direction`, `:size`, `:percent`, `:before` and `:full-size` control placement;
`:detached t` is the default. An emptied source window and all its links are
destroyed. With `:detached nil`, tmux chooses the session context of the physical
destination. Percentage sizing follows the installed tmux semantics: with
`:full-size t`, 3.3a uses the destination pane's dimensions while 3.8 uses the
whole window. Use `:size` for cell-based control.

`break-pane` takes the pane, its explicit source link, a destination session
and a free index. This source link matters when the pane is its window's only
pane: tmux moves that link while preserving other links and the physical window.
The outcome contains the destination link. Its optional `:name` is literal.

Tmux 3.7 has an inverted new-window naming branch, corrected in 3.7a. The
library selects the safe branch from the live pane count within the guarded
request. For a new window with an explicit name, it follows the break with
`rename-window` targeting the moved pane. This adds no subprocess or retry,
but can run an `after-rename-window` hook and is not transactional: a failing
hook can leave the pane moved and renamed. Inspect the retained command
outcome before deciding what to do next. Unnamed single-pane moves keep their
existing name and automatic-rename setting.
See [`cmd_break_pane_exec` in 3.7](https://github.com/tmux/tmux/blob/3.7/cmd-break-pane.c#L116-L123)
and [the corrected 3.7a branch](https://github.com/tmux/tmux/blob/3.7a/cmd-break-pane.c#L116-L123).

`swap-panes` preserves physical IDs and returns replacements in argument order.
`rotate-window` moves pane positions `:up` (default) or `:down` and advances
the active pane. Both accept `:preserve-zoom t`. Placement operations preserve
older observations; a successful operation may have a separate observation
failure. Unlink has no replacement to observe.

## Pane processes

`respawn-pane` restarts its process. `respawn-window` restarts the physical
window as one pane, retaining its first pane and destroying every other pane,
including through other session links. Neither kills a running process unless
`:kill t` is supplied. Omit both `:command` and `:shell-command` to reuse the
stored command; explicit argv, shell text, cwd and environment follow creation.
By default, `outcome-value` supplies a new observation. Earlier captures remain
local and unchanged. A fast-exiting process can disappear before acquisition.

`pipe-pane` accepts explicit `:shell-command` source. It preserves literal `#`
and `%` text by default; `:format-p t` enables tmux format and time expansion
before the shell runs. Literal commands must fit tmux's 8,191-byte time-format
capacity after format escaping. `:direction` is `:output` (pane to shell),
`:input` (shell to pane) or `:both`. Omitting the command closes the pipe.
`:toggle t` closes an existing pipe without starting its replacement.

Pipe success acknowledges configuration. It does not prove shell startup,
command success or data consumption. Coordinate dependent work through an
application signal. Tmux owns the pipe child, and closing the library client
leaves it running. Pipe replacement or explicit closure releases the pane's
connection to that child.

## Buffers

`list-buffers` returns a fresh vector of plists with `:buffer/name`, `:buffer/size`
in bytes and `:buffer/created` in Unix seconds. It preserves tmux's listing
order, limits decoding to 10,000 rows by default, and returns `#()` when empty.
Names are mutable locators, not captured entity identities.

`set-buffer` accepts a literal NUL-free string or an octet vector. Octets travel
through tmux's stdin buffer loader and preserve NUL and invalid UTF-8. `:append t`
is supported for strings. `show-buffer` returns owned octets without decoding.
Both accept a literal `:name`; setting without a name creates an automatic buffer.
Creation through set/load rejects backslashes, ASCII controls and DEL before
I/O because tmux versions otherwise rewrite or reject them. Spaces and Unicode
are supported. Looking up an existing buffer preserves its actual name.

`show-buffer` uses one ordinary unattached tmux client with stdout reserved for
buffer bytes. The same live server guard, operation budget and alias audit apply.
It succeeds only after normal process completion and complete pipe draining,
with exit zero and empty stderr. A hook cannot hide an error by changing its
exit status. Post-launch read failure retains partial output and diagnostics;
it does not prove that the read was never dispatched. Buffer contents are never
parsed as receipts or errors. This contract does not apply to control mode.

`load-buffer` and `save-buffer` take literal file-path strings; `:name` selects
the buffer. Save overwrites unless `:append t` is supplied. Relative paths follow
the tmux command client's cwd. A literal file named `-` must be spelled `./-`;
use set/show for in-memory bytes. Empty input or an empty loaded file is tmux's
no-op and preserves any existing buffer.
Save success records tmux's reported completion; it does not independently
verify file contents or durability. Tmux 3.3a can suppress some file-write errors.

`paste-buffer` takes a physical pane and optional `:name`. Newlines become Return
by default. `:raw t` preserves them; a separate `:separator` string replaces
each newline. `:bracketed t` requests bracket markers when the pane enabled
bracketed paste. `:verbatim t` preserves all bytes, disables newer tmux control-byte
sanitization, and cannot add separators or bracket markers. It chooses flags
from the live daemon version. `:delete t` removes the selected buffer after pasting. Input
disablement and application consumption remain tmux/application concerns.

`delete-buffer :name` requires tmux 3.4 or newer. On 3.3a it signals
`unsupported-capability` before dispatch, because that release can delete an
unrelated top buffer when a named buffer is missing. The condition exposes
`error-feature`, `error-required-version` and `error-actual-version`; the check
uses the live daemon's version, independently of the selected executable.

Omitting a buffer name for show, save, paste or delete uses tmux's default:
the newest buffer on 3.3a, and the newest **automatic** buffer from 3.4 onward.
It does not select the newest explicitly named buffer on modern tmux.

## Configuration mutations

[`set-option`](api.md#set-option-function) and
[`unset-option`](api.md#unset-option-function) address one explicit tmux option
table. Server and global scopes reject a target. Session, window and pane
scopes require a captured target of that type, so the normal generation and
last-moment target guards apply. The exact live daemon version selects the
reviewed option catalog after preflight; the executable's version cannot
silently substitute for it. The current catalogs cover the twelve exact
supported releases from 3.3a through 3.8. An unreviewed neighboring release
signals an error; see [capabilities and current limits](capabilities.md).

Literal writes validate the catalog's native Boolean, integer, choice and text
type before payload dispatch. `nil` is a valid false option value and becomes
tmux `off`. `:format-p t` instead accepts explicit tmux format text and lets the
daemon validate its expanded value. Registered array elements use `:key` and
never allocate a vector by the greatest numeric key. Without `:key`, an array
value uses the option's native tmux list grammar and may create several entries;
use `:key` when the value must remain one literal entry. `:append t` is accepted
only where tmux implements it: strings, keyed string-array values and unkeyed
array assignment. Public user-option writes accept the reversible
`@[A-Za-z0-9_.-]+` name grammar.

[`set-hook`](api.md#set-hook-function) accepts explicit tmux command source; it
does not parse the source as Lisp or execute it locally. Ordinary installation
never uses tmux's immediate-run flag. Tmux can still run a registered native
after-hook such as `after-set-hook` as a consequence of processing the command.
Keyed hook entries do not support appending command text; unkeyed append adds
hook entries through tmux's array grammar. Use
[`unset-hook`](api.md#unset-hook-function) to remove the hook. Registered hooks
stay separate from ordinary option writes, and the live catalog gates dynamic
event sources.

[`set-environment`](api.md#set-environment-function) writes one raw global or
captured-session environment table. It accepts literal text by default,
explicit format expansion through `:format-p t`, and tmux's hidden flag.
[`unset-environment`](api.md#unset-environment-function) deletes an entry;
[`remove-environment`](api.md#remove-environment-function) stores tmux's
removal marker. A tombstone, absence and a present empty string remain distinct.
Names use `[A-Za-z_][A-Za-z0-9_]*` so later named acquisition is reversible.

All seven operations return a
[`command-outcome`](api.md#command-outcome-type), retain effective arguments
and diagnostics, and never retry uncertain mutations. Decoded configuration
readers remain under development; use [`run-command`](api.md#run-command-function)
only when raw tmux argv and its weaker target contract are intentional.

## Explicit termination

[`kill-pane`](api.md#kill-pane-function),
[`kill-window`](api.md#kill-window-function) and
[`kill-session`](api.md#kill-session-function) accept one captured physical
target. The same preflight and last-moment guards used by other named mutations
reject a missing, replaced or foreign-generation target. These functions do not
expose tmux's broad `-a` forms. Killing a physical window removes all its links;
killing a session removes that session's links and any now-unreferenced panes.

[`kill-server`](api.md#kill-server-function) is deliberately separate from
[`close-client`](api.md#close-client-function). Closing releases library-owned
resources and leaves tmux alive. Server termination succeeds only after a
pre-dispatch receipt and readiness of the pidfd retained for the daemon accepted
during this call's preflight prove both dispatch and process exit. Daemon death
without the receipt remains `:unknown` because another actor could have
terminated it. After observed death, the client remains open but its generation
is invalidated; retained captures still support local traversal and projection.

All four operations are destructive and never retry automatically. Select the
target once, establish cardinality before dispatch, and inspect a retained
condition outcome when completion is uncertain.

## Outcomes and target checks

Mutators return `command-outcome`. `outcome-value` returns a value and presence
as two values. Rename and selection accept `:observe nil` to omit follow-up
acquisition. Otherwise a successful mutation followed by failed acquisition
still has status `:succeeded`, no value, and an `outcome-observation-error`.

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

The outcome retains exit status, diagnostic bytes, effective arguments and
elapsed time. A failed command queue can have completed effects; it does not
imply rollback. An unknown mutation is never automatically retried.

Validation checks the live server generation and captured entity identity.
The dispatch connection checks the daemon again and checks physical targets or
session/index/window mappings immediately before the payload. A reused link
index signals `stale-target`. These checks do not make selection and mutation
a transaction; tmux hooks and other clients can change state.

Capture preserves whitespace and trailing lines. The text API strictly decodes
UTF-8; decoding failures retain the client and raw command outcome. The byte API
copies output without decoding. Its flags expose tmux's history, wrapping,
alternate-screen, pending-output and escape modes; they do not reconstruct
terminal bytes that tmux did not retain.

## Command aliases and daemon configuration

Named APIs require the original built-in command meanings and stable
`command-alias` configuration during each call. `show-options` is the trusted
bootstrap spelling used to inspect aliases. It must remain the built-in command.
The audit cannot safely inspect an arbitrary override of itself or prevent
configuration changes after inspection.

Before acquisition or a named operation, the library reads `command-alias` and
signals `unsupported-configuration` for collisions with reserved command names.
`error-setting` identifies the option; `error-commands` returns the colliding
spellings. The reserved list is maintained in
[command-policy.lisp](../src/command-policy.lisp). Other alias names are allowed.
The check conservatively rejects an apparent reserved assignment on any line
of a multiline alias value.

Configured tmux hooks keep their ordinary behavior. The library does not remove
aliases or hooks from the user's daemon. `run-command` remains an explicit raw
escape hatch with tmux's command grammar and no captured-target or alias audit.
