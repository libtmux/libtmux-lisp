# check-source

Fails on trailing whitespace or a missing final newline in tracked and
unignored `.lisp`, `.asd`, `.md`, `.toml` and `.yml` files. `mise run check`
runs it.

```console
$ mise exec -- sbcl --script scripts/check-source/check-source.lisp
```

Tests: `mise run scripts`.
