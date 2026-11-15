# check-documentation-artifact

Validates `docs/_build/api.json`, the exported API artifact: schema, source
revision and hashes, package inventory, declarations, method applicability,
authored cross-references and the `libtmux:client` capability directory.
`mise run check` and `mise run docs-artifact` run it after
`tools/documentation.lisp artifact`.

```console
$ mise exec -- sbcl --script scripts/check-documentation-artifact/check-documentation-artifact.lisp
```

Tests: `mise run scripts`.
