# Captured objects

`fetch-snapshot` reads the selected daemon and returns a native CLOS graph.
Acquisition checks the [supported command-alias configuration](operations.md#command-aliases-and-daemon-configuration)
before listing state.
`sessions`, `windows`, `panes`, `window-links` and `clients` then return fresh
vectors from that observation. These getters, field access, printing,
`same-entity-p` and `entity-data` perform no tmux calls. Captured objects remain
usable after the client closes.

`fetch-sessions`, `fetch-windows`, `fetch-panes` and `fetch-clients` acquire a
complete graph and return the corresponding vector. Repeated fetches read
again. Retain one snapshot when several operations should inspect the same
observation. Filtering a retained vector will use ordinary sequence functions;
the separate [`libtmux/query`](queries.md) system also provides validated local
filters, relation quantifiers and eager QuerySets.

## Entities, links and order

A snapshot contains each physical session, window and pane once. A
`window-link` records a session, index and expected physical window. Linking a
window twice into one session creates two links; linking it elsewhere creates
another. Session-relative active-window state belongs to the link.

| Accessor | Captured result |
| --- | --- |
| `sessions snapshot` | Physical sessions in tmux's observed order |
| `windows snapshot`, `panes snapshot` | Physical entities in first-occurrence order |
| `window-links snapshot` | Every contextual link in listing order |
| `window-links session` | That session's links in observed index order |
| `windows session` | One window per link; repeated physical windows remain repeated |
| `panes window` | Physical panes in captured pane order |
| `window-links window` | Every link to that physical window |
| `window pane`, `window link` | The captured physical window |
| `session link`, `session attached-client` | The captured session |
| `clients snapshot`, `clients session` | Attached-client rows, preserving order and multiplicity |

An attached tmux client is an `attached-client` observation. It is distinct from
the library's connection `client`. Repeated target names are retained; a name
does not establish identity.

## Values and ownership

`field-value` returns value and presence as two values. Present false is
`nil, t`; an absent optional field is `nil, nil`. Empty names and pane titles
are present strings. Current command/path may be absent when tmux reports an
empty value. An empty or zero pane PID is absent, while the captured dead flag
retains the daemon version's reported meaning. Never infer one from the other.

The convenience readers `name`, `active-p`, `width`, `height`, `index`,
`current-command`, `current-path`, `title` and `dead-p` follow the same presence
contract. Paths remain text from tmux; they are not normalized as local paths.
Unknown fields and unloaded relations signal `field-unavailable`.

Every public mutable result is owned by the caller: strings, relation vectors,
provenance and projection containers are copied. Entity observations can be
shared between result vectors. Changing a returned vector or string does not
change the capture. Deliberate private-slot mutation is unsupported.

`entity-data` returns a finite plist with captured fields, provenance and
relationship identifiers. It omits absent optional fields and retains present
false values. It contains no operational handles or recursive object graph.
Use `id` to inspect identity: physical IDs are strings; link IDs are
`(session-id index expected-window-id)`; attached-client row IDs have meaning
only within that observation.

## Identity and refresh

`same-entity-p` compares model, connection context, generation and captured ID.
Two clients have distinct contexts even when connected to the same daemon.
Window-link identity retains its expected window and index; the index is a
mutable locator. Attached-client identity is scoped to one snapshot.

`refresh` takes the connection client and an existing entity or snapshot. It
acquires a replacement without changing the old observation. A different
server generation, missing target or changed link mapping signals
`stale-target`. Refreshing an attached client requires a unique live target
name and matching PID, creation time and tty presence; the returned object's
observation identity is new.

The native Linux witness includes daemon PID, daemon startup, socket inode and
device, kernel process-start identity and a retained pidfd. This distinguishes
server replacement even if tmux reuses its numeric IDs and startup second.
The daemon version and selected executable version are recorded separately.

Acquisition first verifies the selected endpoint, then pins subsequent commands
to its canonical path. Every listing carries a tagged witness produced on the
same server connection as its rows, including an empty listing. A changed peer
invalidates the attempt. Final continuity checks detect server replacement and
persistent selected-endpoint changes. This does not make graph acquisition
transactional: tmux state can change between the listing commands.

A successful nonempty capture uses five tmux launches: alias audit, initial
witness, session listing, a batch of window-link/pane/client listings, and final
witness. Each batched listing has its own connection witness, and both outer
witnesses retain the full process/socket checks. A live empty daemon uses four
launches. Counts exclude client opening and retries.

The batch has one command outcome. A framing or witness failure retains that
outcome; it does not invent an outcome for each listing. Row limits remain per
listing, while stdout and stderr across all launches share the total byte cap.
Hooks can change state inside a batch, so graph validation and bounded retries
remain necessary.

## Bounds and failures

Provenance records monotonic acquisition bounds and Common Lisp universal-time
bounds, as well as tmux's Unix server-start time. Duplicate physical rows must
agree. References, contextual pane order, counts and active states are checked.
Contradictory captures retry at most twice, then signal `incomplete-snapshot`.
Retries share the original deadline and byte budget.

The default total timeout is 30 seconds and total output cap is 16 MiB, inherited
from the client. Defaults also bound each listing to 100,000 rows, the graph to
100,000 entities, and each encoded field to 1 MiB. `:timeout`, `:output-limit`,
`:row-limit`, `:entity-limit`, `:field-limit` and `:cancel-token` configure these
limits on fetch operations. Decoding and graph construction check cancellation
and the same deadline as subprocess work.

A confirmed live daemon with zero sessions returns empty vectors. A missing
daemon or failed listing signals a condition; neither becomes an empty result.
Acquisition uses tmux's no-start option and never starts a daemon implicitly.
The current core observes entities reachable from sessions; it does not claim
an inventory of detached internal tmux objects outside that graph.
