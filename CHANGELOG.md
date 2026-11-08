# Changelog

## Unreleased

### Fixed

- Preserve partial and uncertain command outcomes in workspace CLI JSON errors,
  including nested causes, failed steps and raw diagnostic bytes.

### Added

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
