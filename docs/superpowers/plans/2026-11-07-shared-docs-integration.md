# Shared documentation integration plan

**Goal:** Publish the implemented Common Lisp core and workspace documentation
through the shared libtmux.org model without inventing package availability or
parsing Lisp source in JavaScript.

**Architecture:** SBCL exports one bounded, revision-bound JSON artifact from
loaded public packages, native docstrings, lambda lists, CLOS metadata and
definition sources. The shared docs repository validates and adapts that
artifact into its existing Astro API model, then stages authored guides from
the same source revision. Common Lisp owns no MCP product; the site records it
as excluded.

### Task 1: Native documentation artifact

- Extend `tools/documentation.lisp` with a deterministic JSON artifact writer.
- Record library and exporter revisions separately, source paths and hashes,
  native signatures, symbol kinds, package ownership, docstrings and authored
  cross-references.
- Add a focused contract check, a `mise` task and freshness coverage.
- Prove the artifact against a clean committed source revision.

### Task 2: Shared API adapter and port registration

- Add `lisp` to the shared API model and implement a strict artifact adapter.
- Register Common Lisp, its source checkout/worktree, source installation,
  core/workspace product availability and excluded MCP status.
- Inventory the public ASDF systems and CLI accurately as source-installed and
  unreleased.
- Add focused adapter, registration, inventory and version tests first.

### Task 3: Guides, generated model and branding

- Stage the port-owned guides from the same reviewed source revision.
- Generate API model, navigation, paths, guide cache and manifest inventory.
- Reuse the pending shared Common Lisp artwork from libtmux/docs PR #263; do
  not duplicate or republish its assets.
- Add landing/reference examples only from executed port source.

### Task 4: Publisher and acceptance

- Add the port caller only after the shared workflow revision exists and pin
  both the reusable workflow and checkout to that exact full revision.
- Run focused tests, shared-site checks and a complete source-bound Lisp build.
- Inspect reference links, anchors, navigation, assets and narrow layouts in a
  local preview.
- Push the isolated shared-site branch and open an early draft PR with exact
  source/exporter revisions, timings, publication still pending and branding
  dependency called out.
