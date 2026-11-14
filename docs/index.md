# libtmux-lisp documentation

Start with the [REPL tutorial](tutorial.md): install, acquire, filter, build
workspaces, inspect outcomes. Examples run on SBCL.

Pick optional systems from the
[ASDF system directory](../README.md#choose-an-asdf-system). Each has its own
README.

| Guide | Purpose |
| --- | --- |
| [Tutorial and recipes](tutorial.md) | Runnable workflows and expected results |
| [Captures and identity](captures.md) | Object graph, relations, presence, ownership and refresh |
| [Native queries](queries.md) | Typed forms, relations, QuerySets, limits and cardinality |
| [Query interchange](query-interchange.md) | Optional regex and bounded versioned JSON documents |
| [Owned workspaces](workspace-owned.md) | Logical IDs, declarations, previews, reconcile, inspection, CLI |
| [Legacy workspace topology](workspaces.md) | Schema /1 creation and topology-only reuse |
| [Decoded configuration](configuration.md) | Typed values, inheritance, hooks, environment state and failure evidence |
| [Explicit operations](operations.md) | Creation, placement, input, buffers and mutation outcomes |
| [Transport](transport.md) | Client lifecycle, limits, cancellation and failure evidence |
| [Persistent control](control.md) | Nonblocking submission, byte output, cancellation, connection scopes |
| [Control API](control-api.md) | Generated resource, request, event and recovery reference |
| [Daemon scopes](daemons.md) | Private foreground startup, readiness, environment and checked shutdown |
| [Architecture decision](adr/0001-native-common-lisp-engine.md) | Engine boundaries, captured model and trade-offs |
| [Public API](api.md) | Generated signatures, docstrings, classes and conditions |
| [Query API](query-api.md) | Generated query, QuerySet, condition and operator reference |
| [Query JSON API](json-api.md) | Generated codec signatures and document conditions |
| [Workspace API](workspace-api.md) | Generated workspace, plan, result, condition and CLI reference |
| [Captured fields](fields.md) | Generated typed field/relation registry |
| [Capabilities and limits](capabilities.md) | Platform, concurrency, planned modules, gaps |
| [Benchmarks](benchmarks.md) | Native read paths and acquisition cost |
| [Testing](testing.md) | FiveAM workflow and isolated tmux |
| [Source modules](modules.md) | Generated implementation responsibility map |

Reproduce and verify:

- [Verification](../verification.md)
- [Toolchain and dependency setup](../.github/CONTRIBUTING.md#setup)
- [Source examples](../examples/workspace.lisp)
- [Workflow](../.github/workflows/tests.yml)

At the REPL, call `documentation` on a public function or class. SLY and SLIME
show the same docstrings and lambda lists.
