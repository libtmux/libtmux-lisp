# libtmux-lisp documentation

Start with the [REPL tutorial](tutorial.md): install, acquire, inspect the
graph, filter locally, build linked workspaces and inspect operation outcomes.
All examples use the native SBCL implementation.

| Guide | Purpose |
| --- | --- |
| [Tutorial and recipes](tutorial.md) | Runnable workflows and expected results |
| [Captures and identity](captures.md) | Object graph, relations, presence, ownership and refresh |
| [Native queries](queries.md) | Typed forms, relations, QuerySets, limits and cardinality |
| [Query interchange](query-interchange.md) | Optional regex and bounded versioned JSON documents |
| [Declarative workspaces](workspaces.md) | Bounded documents, pure plans, explicit apply and CLI |
| [Explicit operations](operations.md) | Creation, placement, input, buffers and mutation outcomes |
| [Transport](transport.md) | Client lifecycle, limits, cancellation and failure evidence |
| [Persistent control](control.md) | Nonblocking submission, byte output, cancellation and owned connection scopes |
| [Control API](control-api.md) | Generated resource, request, event and recovery contracts |
| [Daemon scopes](daemons.md) | Private foreground startup, readiness, environment and checked shutdown |
| [Architecture decision](adr/0001-native-common-lisp-engine.md) | Engine boundaries, captured model, alternatives and trade-offs |
| [Public API](api.md) | Generated signatures, docstrings, classes and conditions |
| [Query API](query-api.md) | Generated query, QuerySet, condition and operator reference |
| [Query JSON API](json-api.md) | Generated codec signatures and document conditions |
| [Workspace API](workspace-api.md) | Generated workspace, plan, result, condition and CLI reference |
| [Captured fields](fields.md) | Generated typed field/relation registry |
| [Capabilities and limits](capabilities.md) | Platform, concurrency, planned modules and adoption gaps |
| [Testing](testing.md) | FiveAM's interactive workflow and isolated tmux CI |
| [Source modules](modules.md) | Generated implementation responsibility map |

For reproducibility, see [verification](../verification.md),
[toolchain and dependency setup](../.github/CONTRIBUTING.md#setup),
[source examples](../examples/workspace.lisp) and the
[workflow](../.github/workflows/tests.yml). API and field pages are generated
from the loaded Lisp system; excerpts come from executed example files.

At the REPL, use `documentation` on a public function or class. In SLY or SLIME,
the same documentation and real lambda lists support symbol help and source
navigation. No browser-specific annotations replace the Lisp docstrings.
