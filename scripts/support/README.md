# support

Shared helpers for the scripts in this directory: failures that exit 1 with a
message, child processes with deadlines, text and JSON files, SHA-256 digests
and temporary directories. Each script loads `tools/load.lisp`, then
`support.lisp`; it has no entry point of its own.

The JSON reader and writer keep object order and write two-space indentation
and non-ASCII text as is, so a regenerated file differs from the committed
one only when its content changed. Tests: `mise run scripts`.
