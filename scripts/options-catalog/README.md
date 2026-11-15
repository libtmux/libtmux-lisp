# options-catalog

Generates `src/options-catalog.lisp` from `data/options-catalog.json`, the
tmux option facts for each supported release, and refreshes those facts from
tmux source.

- `options-catalog.lisp [check|write]`: `check` fails when the generated file is
  stale (`mise run check`); `write` regenerates it (`mise run catalogs`).
- `options-catalog.lisp import --source-catalog FILE`: folds an extractor
  catalog into `data/options-catalog.json`, then regenerates.
- `extract-options-catalog.lisp --tmux-source PATH`: reads the commits pinned in
  `tools/tmux-sources.json` from a tmux Git checkout, expands macros with the
  host `cc`, reads the option table with a restricted C reader and checks every
  field against a compiled view (`compiled-schema.c`). Unknown C fails. The
  output goes to `build/options-catalog/`. Maintainers run it outside the inner
  and mid loops; see [CONTRIBUTING](../../.github/CONTRIBUTING.md).

Tests: `mise run scripts`.
