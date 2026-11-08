# Changelog

## Unreleased

### Fixed

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
