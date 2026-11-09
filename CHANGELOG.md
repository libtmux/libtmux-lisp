# Changelog

## Unreleased

### Fixed

- Preserve dollar-prefixed captured text on tmux 3.4 and control characters on
  tmux 3.4–3.5a. Encode fields before native printing so names retain their
  values and socket witnesses resolve the original endpoint.

- Preserve hash runs before `[` in literal names, paths and pipe commands.
  Tmux keeps those runs during format expansion; doubling them changed stored
  names and could make a requested working directory fall back elsewhere.

- Preserve named and unnamed `break-pane` behavior on tmux 3.7 despite its
  inverted naming branch. Retain partial outcomes when a rename hook fails.

- Report unsupported runtime facilities before resolving the tmux executable.
  Probe failures retain their requirement and cause; script or shim errors
  identify the selected file and the underlying-binary option.

- Preserve partial and uncertain command outcomes in workspace CLI JSON errors,
  including nested causes, failed steps and raw diagnostic bytes.

### Changed

- Reduce nonempty capture acquisition from seven tmux launches to five, keeping
  fresh daemon witnesses, per-listing bounds and contradiction retries.

### Added

- Add decoded option, hook and named environment readers with exact live-catalog
  types, presence-aware lookup, sparse arrays and explicit inherited sources.
  Preserve hidden/removal state, shared limits and native failure evidence;
  returned records own their mutable data.

- Add literal user/group server ACL operations and native listing output,
  preserving versioned frontend permission updates and command outcomes.

- Add command/key printer inspection and single-key binding/removal with
  explicit argv versus tmux source, parser effects and future key execution.

- Add literal message printing with explicit tmux format expansion, captured
  target context, preserved printer text and retained command outcomes.

- Add session-wide and server-wide frontend lock requests with retained
  command outcomes and explicit request-versus-frontend completion semantics.

- Add explicit wait-channel signal, wait, lock and unlock requests. Blocking
  operations require tmux 3.8's disconnected-waiter cleanup; locks stay explicit.

- Add captured terminal-client switching, redraw, detach, suspend and lock
  requests with explicit authority, environment policy and retained outcomes.

- Accept function objects and global function names in QuerySet filtering,
  ordering and key selection, resolving each once per operation.
- Add the separately loadable `libtmux/query` system with typed scalar filters,
  bounded owned query data, local predicates, fresh-vector matching, defensive
  inspection and strict cardinality.
- Add registered relationship quantifiers and eager, non-destructive QuerySet
  operations with explicit model metadata and stable private-copy ordering.
- Add separately loadable CL-PPCRE search/full-match operators and bounded Jzon
  filter documents without widening the core/query dependency boundary.
- Add typed option, hook and environment mutations with exact live-catalog
  validation, explicit table scopes and guarded command outcomes.
- Add exact pane, window and session deletion plus separately proven server
  termination with retained dispatch, pidfd and uncertainty evidence.
