# libtmux-lisp

Common Lisp port of libtmux, at the repository bootstrap stage.

The ASDF system is named `libtmux`. Its `0.0.0` version marks an unreleased
scaffold with no source components, public API, or tmux behavior.

## Development

[.tool-versions](.tool-versions) pins SBCL 2.6.10 and ASDF 3.3.7 for Linux
x86-64, including WSL. Use mise 2026.11.3 or newer.
[mise.toml](mise.toml) supplies download settings and tasks. ASDF is Common
Lisp's build system; asdf-vm is not required.

Follow the [setup instructions](.github/CONTRIBUTING.md), then validate the
system definition:

```console
$ mise run check
```

Loading this empty system checks the package metadata. It does not establish
runtime behavior or compatibility with other Lisp implementations or hosts.

See [AGENTS.md](AGENTS.md) for change discipline and
[WRITING.md](.github/WRITING.md) for prose and commit conventions.

## Scope

The next design phase covers the core library, separate MCP and workspace
packages, and documentation. Implementation and CI have not started.
Development targets current stable tooling; older-version compatibility is
outside the present scope. Future runtime work targets tmux 3.8 or newer.
The project license remains undecided.
