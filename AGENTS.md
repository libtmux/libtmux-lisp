# Agent instructions

This repository is a standalone Common Lisp port of libtmux. Bootstrap work
ends at package metadata, tool configuration, and contributor instructions.
Start architecture or implementation only when requested.

## Change discipline

- Preserve existing files, symlink targets, unrelated changes, and worktrees.
- Make the smallest coherent change that solves the requested problem.
- Reuse existing files, helpers, APIs, and tests before adding new ones.
- Keep new APIs private until an external caller needs them. Add files for
  distinct responsibilities or independent reuse, not one-line re-exports.
- Add tests only for critical behavior. Show that a regression test fails for
  the intended reason before relying on its passing result.
- Prefer `rg`, `ag`, and `fd` for discovery; use `jq` for JSON.
- Follow native Common Lisp conventions. Sibling ports provide behavioral
  references; their test results do not establish support in this port.
- Use mise for toolchain management. ASDF means the Common Lisp build system,
  not asdf-vm. Target current stable releases without legacy compatibility
  shims unless the requested scope changes.
- Do not turn successful metadata loading into a claim of implemented behavior.
- Report verification as `PASS`, `FAIL`, `PARTIAL`, or `UNVERIFIED`, with the
  commands and whole-command elapsed times.
- Local edits do not authorize commits, remote changes, pushes, or releases.
  Honor any explicit authorization already supplied in the current session.

## Guides

- Setup, verification, tmux isolation, and pull requests:
  [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md).
- Documentation, comments, and commit messages:
  [.github/WRITING.md](.github/WRITING.md).

`CLAUDE.md` is a relative symlink to this file. Keep shared instructions here.

## Merging pull requests

Use a descriptive subject ending in the actual PR number: `Title (#PRNUM)`.
Follow it with `what:` and `why:` sections describing the change and reason.
Pass both explicitly to the merge command and read back the resulting commit
message. Do not use the default `Merge pull request ... from ...` subject.
