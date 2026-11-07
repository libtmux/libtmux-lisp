# libtmux-lisp

Native Common Lisp library for tmux, targeting SBCL on Linux.

Implementation is in progress. Client scopes, bounded subprocess commands,
cancellation, captured CLOS graphs and owned command outcomes are implemented.
Named creation, rename, selection, geometry, placement, buffer, process and input
operations are available with target validation and explicit outcomes.
Queries and the optional consumers are still in development. The `0.1.0`
system version is unreleased.

## Development

[.tool-versions](.tool-versions) pins SBCL 2.6.10, ASDF 3.3.7 and Qlot 1.8.4 for Linux
x86-64, including WSL. Use mise 2026.11.3 or newer.
[mise.toml](mise.toml) supplies download settings and tasks. ASDF is Common
Lisp's build system; asdf-vm is not required.

Follow the [setup instructions](.github/CONTRIBUTING.md), then run source and
unit checks:

```console
$ mise run check
```

Run transport and owned tmux integration tests separately:

```console
$ mise run integration
```

See [verification.md](verification.md) for commands and the current evidence
boundary. Loading package metadata does not establish engine compatibility.
The [testing guide](docs/testing.md) covers FiveAM at the REPL, test redefinition,
rerunning tests, debugger entry and cached GitHub Actions builds.

The current process backend requires Linux x86-64 with pidfd process-group
signalling (kernel 6.9 or newer) and Bash. It checks these capabilities when
opening a client. Select a native ELF tmux executable; script wrappers are not
accepted. See the [client and transport contracts](docs/transport.md).
The [capture contract](docs/captures.md) describes local traversal, ownership,
window links, identity and refresh.
The [operations guide](docs/operations.md) covers names, child commands, input,
outcomes and daemon configuration requirements.

See [AGENTS.md](AGENTS.md) for change discipline and
[WRITING.md](.github/WRITING.md) for prose and commit conventions.

## Scope

The suite includes native captured objects, ordinary Lisp sequences, a query
compiler, optional regex/JSON/control systems, MCP and workspace consumers,
and executable documentation. The selected tmux floor is 3.3a; plain 3.3 is
unsupported. Exact compatibility tests remain required before release.

Licensed under [MIT](LICENSE).
