# support

Shared helpers for the scripts in this directory: failures that exit 1 with a
message, child processes with deadlines, text and JSON files, SHA-256 digests
and temporary directories. Each script loads `tools/load.lisp`, then
`support.lisp`; it has no entry point of its own.

The JSON reader and writer keep object order and match Python's
`json.dumps(indent=2, ensure_ascii=False)`, so generated files stay
byte-identical. Tests: `mise run scripts`.
