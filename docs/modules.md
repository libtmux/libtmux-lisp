# Source modules

Generated from ASDF component descriptions by `mise run docs`.
These files implement the core `libtmux` system; their internal package is private.

[Public API](api.md) · [Architecture and boundaries](captures.md)

| Source | Responsibility |
| --- | --- |
| [src/package](../src/package.lisp) | Public and internal packages; connection, observation and operation contracts. |
| [src/conditions](../src/conditions.lisp) | Typed failure conditions and retained diagnostic readers. |
| [src/transport](../src/transport.lisp) | Owned command outcomes, cancellation tokens and transport validation. |
| [src/backend-sbcl](../src/backend-sbcl.lisp) | SBCL/Linux synchronization and native operating-system capability checks. |
| [src/process-sbcl](../src/process-sbcl.lisp) | Bounded subprocess lifecycle, nonblocking pipe service and cleanup ownership. |
| [src/client](../src/client.lisp) | Connection scopes, single-operation leases and explicit raw tmux commands. |
| [src/command-policy](../src/command-policy.lisp) | Required built-in command meanings and daemon alias validation. |
| [src/registry](../src/registry.lisp) | Typed captured fields, relationships and wire scalar validation. |
| [src/records](../src/records.lisp) | Reversible bounded tmux row framing and strict text decoding. |
| [src/model](../src/model.lisp) | Captured CLOS observations, local readers, identity and owned projections. |
| [src/graph](../src/graph.lisp) | Physical-entity normalization, explicit window links and graph consistency. |
| [src/witness-sbcl](../src/witness-sbcl.lisp) | Server generation authority using socket and Linux process identities. |
| [src/capture](../src/capture.lisp) | Explicit bounded acquisition and replacement observations. |
| [src/command-encoding](../src/command-encoding.lisp) | Literal, format, argv and shell-source boundaries for tmux commands. |
| [src/configuration-codec](../src/configuration-codec.lisp) | Private bounded decoding of inert tmux quoted-data values. |
| [src/dispatch](../src/dispatch.lisp) | Target guards, dispatch evidence and independent observation outcomes. |
| [src/operations](../src/operations.lisp) | Rename, select and terminal capture operations with explicit clients. |
| [src/creation](../src/creation.lisp) | Detached session/window/pane creation from argv or explicit shell source. |
| [src/process-operations](../src/process-operations.lisp) | Explicit pane respawn and daemon-owned shell pipe configuration. |
| [src/terminal-operations](../src/terminal-operations.lisp) | Literal text, key input, prefix, copy mode and history operations. |
| [src/geometry](../src/geometry.lisp) | Bounded pane/window dimensions and tmux layout operations. |
| [src/selection](../src/selection.lisp) | Contextual next, previous and last window/pane selection. |
| [src/placement](../src/placement.lisp) | Physical pane placement and contextual window-link operations. |
| [src/buffers](../src/buffers.lisp) | Owned binary buffers, file transfer and explicit pane paste operations. |
