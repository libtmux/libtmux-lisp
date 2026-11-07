# Workspace v1 implementation plan

> **For Codex:** Execute this plan with `superpowers:executing-plans`, one task
> at a time. Use `superpowers:test-driven-development` for every behavior.

**Goal:** Add a separate, native Common Lisp workspace system that validates
owned declarative data, plans without I/O, creates a missing topology through
the core API, proves repeat application is a no-op, and retains partial failure
evidence.

**Architecture:** `libtmux/workspace` depends on `libtmux` and the locked Jzon
parser. Its CLOS objects own normalized configuration and expose defensive data.
Pure planning compares a workspace with an optional captured snapshot. Apply is
the only I/O boundary and delegates every mutation to existing core operations.
`libtmux/workspace/cli` remains a thin explicit-endpoint adapter.

**Tech stack:** SBCL 2.6, ASDF/UIOP, FiveAM, com.inuoe.jzon, tmux 3.3a and 3.8.

**Specification:** [Workspace system v1](../../design/workspace-v1.md)

---

### Task 1: Owned native configuration and pure plans

**Files:**

- Create: `src/workspace.lisp`
- Create: `tests/workspace.lisp`
- Modify: `libtmux.asd`
- Modify: `tests/package.lisp`
- Modify: `tools/test.lisp`
- Modify: `mise.toml`

**Interfaces:**

- package `libtmux.workspace`
- classes `workspace`, `workspace-plan`, `workspace-step`
- conditions `workspace-error`, `invalid-workspace`, `workspace-conflict`
- readers `workspace-data`, `plan-steps`, `step-action`, `step-data`
- functions `make-workspace`, `plan-workspace`

**Tests:**

- native data is copied on input and output;
- closed plists, names, indexes, panes, argv, cwd, and layouts are validated;
- offline steps are deterministic and copied on inspection;
- exact synthetic captured topology yields no steps;
- extra, missing, ambiguous, or mismatched topology signals conflict;
- planning makes zero transport calls.

Run `mise run workspace` after the failing test and after implementation.

### Task 2: Bounded complete JSON and file loading

**Files:**

- Modify: `src/workspace.lisp`
- Modify: `tests/workspace.lisp`

**Interfaces:**

- conditions `invalid-workspace-document`, `workspace-limit-exceeded`
- readers `workspace-path`, `workspace-limit`
- functions `parse-workspace`, `read-workspace`

**Tests:**

- the documented JSON produces the same normalized data as native input;
- duplicate/unknown members, null, floats, trailing input, and foreign schemas
  fail without interning external names;
- every declared structural limit fails with its limit name and owned path;
- regular-file and byte bounds are enforced before unbounded allocation.

Run `mise run workspace` after the failing test and after implementation.

### Task 3: Explicit apply with retained evidence

**Files:**

- Modify: `src/workspace.lisp`
- Modify: `tests/workspace.lisp`
- Create: `tests/workspace-integration.lisp`
- Modify: `libtmux.asd`

**Interfaces:**

- class `workspace-result`
- condition `workspace-apply-failed`
- readers `result-snapshot`, `result-outcomes`, `result-created-p`,
  `failed-step`
- function `apply-workspace`

**Tests:**

- owned tmux fixture creates the full session/window/pane graph;
- explicit indexes, inherited cwd, argv, and named layout are observable;
- result outcome containers are defensive;
- second apply performs no mutation and returns no outcomes;
- conflicting existing topology dispatches nothing;
- injected later-step failure retains preceding outcomes and failed step;
- final-proof acquisition failure is distinct from a command failure.

Run `mise run workspace`, then exact-version integration on tmux 3.3a and 3.8.

### Task 4: CLI, API browser, packaging, and executable example

**Files:**

- Create: `src/workspace-cli.lisp`
- Create: `bin/libtmux-workspace`
- Create: `examples/workspace.lisp`
- Create: `examples/workspace.json`
- Create: `docs/workspaces.md`
- Generate: `docs/workspace-api.md`
- Modify: `tools/documentation.lisp`
- Modify: `tools/doc-examples.py`
- Modify: `tools/examples.py`
- Modify: `tools/package.py`
- Modify: `README.md`
- Modify: `docs/index.md`
- Modify: `docs/modules.md`
- Modify: `.github/CONTRIBUTING.md`
- Modify: `libtmux.asd`

**Interfaces:**

- ASDF system `libtmux/workspace/cli`
- `libtmux.workspace.cli:main` with `validate`, `plan`, and `apply`
- explicit `--socket-path` for `apply`; no implicit endpoint

**Tests:**

- CLI validation and offline planning need no daemon;
- CLI apply uses an owned endpoint and prints an inspectable result;
- README/docs excerpts match executable source;
- public symbols have interlinked docstrings and generated API anchors;
- the source archive loads and runs workspace APIs and the example in an
  isolated consumer.

Run `mise run docs`, `mise run check`, `mise run examples`,
`mise run package`, and `mise run package-examples`.

### Task 5: Full acceptance and integration

**Files:**

- Modify only defects found by acceptance/review.

**Checks:**

- run source/unit/query/regex/JSON/workspace/doc checks;
- run full integration against exact tmux 3.3a and 3.8;
- run examples and isolated package consumers;
- run workflow lint;
- obtain independent fresh-context review;
- commit coherent changes, push authorized `master`, and verify every hosted
  exact-head job before reporting PASS.
