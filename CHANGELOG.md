# Changelog

## Unreleased

### Added

- Add the separately loadable `libtmux/query` system with typed scalar filters,
  bounded owned query data, local predicates, fresh-vector matching, defensive
  inspection and strict cardinality.
- Add registered relationship quantifiers and eager, non-destructive QuerySet
  operations with explicit model metadata and stable private-copy ordering.
- Add separately loadable CL-PPCRE search/full-match operators and bounded Jzon
  filter documents without widening the core/query dependency boundary.
