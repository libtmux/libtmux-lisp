# Captured objects

`fetch-snapshot` reads the selected daemon and returns a CLOS graph of captured
objects.

- It checks the
  [supported command-alias configuration](operations.md#command-aliases-and-daemon-configuration)
  before listing state.
- `sessions`, `windows`, `panes`, `window-links` and `clients` return fresh
  vectors from that snapshot.
- Those getters, field access, printing, `same-entity-p` and `entity-data` make
  no tmux calls.
- Captured objects stay usable after the client closes.

One-call fetchers:

- `fetch-sessions`, `fetch-windows`, `fetch-panes` and `fetch-clients` capture a
  complete graph and return one vector. Each call reads again.
- Keep one snapshot when several operations must see the same observation.
- Filter a retained vector with ordinary sequence functions, or with
  [`libtmux/query`](queries.md) (validated filters, relation quantifiers, eager
  QuerySets).

## Entities, links and order

- A snapshot holds each physical session, window and pane once.
- A `window-link` records a session, an index and the expected physical window.
- Every link of a window, in the same session or another, is its own
  `window-link`.
- Session-relative active-window state lives on the link.

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

- An attached tmux client is an `attached-client` observation, distinct from the
  library's connection `client`.
- Repeated target names are kept; a name is not an identity.

## Values and ownership

`field-value` returns value and presence as two values.

- Present false: `nil, t`. Absent optional field: `nil, nil`.
- Empty names and pane titles are present strings.
- Current command and path are absent when tmux reports an empty value.
- An empty or zero pane PID is absent. The dead flag keeps the meaning the
  daemon's tmux version reports. Never infer one from the other.

Convenience readers and unknown fields:

- `name`, `active-p`, `width`, `height`, `index`, `current-command`,
  `current-path`, `title` and `dead-p` follow the same presence rules.
- Paths stay text from tmux. They are not normalized as local paths.
- Unknown fields and unloaded relations signal `field-unavailable`.

Fields keep `%`, `$` and non-NUL ASCII control characters exactly:

- The library encodes each field before tmux prints it, avoiding tmux's visual
  escaping (for example an extra backslash before `$HOME` in some releases).
- Literal backslashes and valid Unicode are unchanged.
- The decoder rejects malformed escapes and invalid UTF-8.
- This keeps the text tmux supplies. It cannot recover filesystem bytes tmux
  already turned into display text.
- So a captured current path is not a filesystem identity or a byte-exact
  filesystem argument.

Ownership:

- Every public mutable result is caller-owned: strings, relation vectors,
  provenance and projection containers are copied.
- Entity observations can be shared between result vectors.
- Changing a returned vector or string never changes the capture.
- Mutating private slots is unsupported.

`entity-data` returns a finite plist:

- Holds captured fields, provenance and relationship IDs.
- Omits absent optional fields; keeps present false values.
- Holds no operational handles and no recursive object graph.

`id` gives identity:

- Physical IDs are strings.
- Link IDs are `(session-id index expected-window-id)`.
- Attached-client row IDs mean something only within that observation.

## Identity and refresh

`same-entity-p` compares model, connection context, generation and captured ID.

- Two clients have distinct contexts, even on the same daemon.
- A window link's identity keeps its expected window and index. The index is a
  mutable locator.
- Attached-client identity is scoped to one snapshot.

`refresh` takes the connection client and an entity or snapshot.

- It returns a replacement; the old observation is unchanged.
- A different server generation, a missing target or a changed link mapping
  signals `stale-target`.
- Refreshing an attached client needs a unique live target name and matching
  PID, creation time and tty presence.
- The returned attached client has a new observation identity.

On Linux, a witness detects server replacement even if tmux reuses numeric IDs
and the startup second. It combines:

- daemon PID and startup
- socket inode and device
- process-start identity and a retained pidfd

Daemon and executable versions are recorded separately.

Acquisition:

- Verifies the selected endpoint, then pins later commands to its canonical
  path.
- Tags every listing, even an empty one, with a witness from the same server
  connection as its rows.
- Discards the attempt if the peer changes.
- Ends with continuity checks for server replacement and persistent endpoint
  changes.

It is not transactional: tmux state can change between listing commands.

Tmux launches per capture (client opening and retries excluded):

- Nonempty: five. Alias audit, initial witness, session listing, one batch of
  window-link, pane and client listings, final witness.
- Live empty daemon: four.

The batch:

- gives each listing its own connection witness; both outer witnesses keep the
  full process and socket checks
- has one command outcome. A framing or witness failure keeps it; no
  per-listing outcomes are invented.
- Row limits apply per listing. Stdout and stderr across all launches share one
  byte cap.
- Hooks can change state inside a batch, so graph validation and bounded
  retries stay.

## Bounds and failures

- Provenance holds monotonic and universal-time acquisition bounds, plus tmux's
  Unix server-start time.
- Duplicate physical rows must agree. References, contextual pane order, counts
  and active states are checked.
- Contradictory captures retry at most twice, then signal
  `incomplete-snapshot`.
- Retries share the original deadline and byte budget.

Default limits on fetch operations, with the keyword that sets each:

- total timeout 30 seconds (`:timeout`) and output cap 16 MiB
  (`:output-limit`), inherited from the client
- 100,000 rows per listing (`:row-limit`)
- 100,000 entities per graph (`:entity-limit`)
- 1 MiB per encoded field (`:field-limit`)

`:cancel-token` cancels a fetch. Decoding and graph construction check
cancellation and the same deadline as subprocess work.

- A live daemon with zero sessions returns empty vectors.
- A missing daemon or failed listing signals a condition; it never becomes an
  empty result.
- Acquisition uses tmux's no-start option and never starts a daemon.
- Only entities reachable from sessions are observed. Detached internal tmux
  objects outside that graph are not inventoried.
