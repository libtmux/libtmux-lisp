# doc-examples

Keeps each `<!-- example:NAME -->` block in the README and guides identical to
the `;;; docs:NAME` region of a file under `examples/`, and checks local links,
images and anchors. `mise run check` fails on a stale excerpt; `mise run docs`
rewrites them.

```console
$ mise exec -- sbcl --script scripts/doc-examples/doc-examples.lisp
```

Add `write` to rewrite the excerpts:

```console
$ mise exec -- sbcl --script scripts/doc-examples/doc-examples.lisp write
```

Tests: `mise run scripts`.
