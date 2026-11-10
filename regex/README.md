<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="../docs/assets/logo.svg" type="image/svg+xml">
    <img src="../docs/assets/logo-512.png" width="128" height="128" alt="libtmux for Common Lisp">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# libtmux/regex

</div>

Add CL-PPCRE search and full-match operators to native captured queries. This
optional ASDF system depends on [`libtmux/query`](../query/README.md) and
CL-PPCRE. Loading or evaluating a filter does not contact tmux.

## Load and use

Complete the root [source setup](../README.md#install-from-source), including
the locked optional dependencies, then load:

```lisp
(asdf:load-system "libtmux/regex")
```

Use `:regex-search` to find a match anywhere in a text field, or
`:regex-full-match` to match its complete value. Both declare the engine with
`(:cl-ppcre pattern options...)`; compilation retains an owned pattern and
prepares the scanner once. The
[checked example](../docs/query-interchange.md#compile-a-reusable-regex) selects
the demo's `cat` panes using an explicit case-insensitive full match.

Run it with the complete examples from the checkout root:

```console
$ mise run examples
```

## Execution boundary

Regex uses CL-PPCRE semantics. A tmux or another language's regex engine need
not interpret the same pattern identically. Query visit limits bound traversal;
they do not interrupt a scanner already executing. An absent field fails the
match.

To exchange filters, also load [`libtmux/json`](../json/README.md) and pass
`:allow-regex t` when decoding regex documents. Core and query remain usable
without either optional system.

[Regex operators and modes](../docs/queries.md#add-optional-regex-operators) ·
[Query API](../docs/query-api.md) ·
[Interchange](../docs/query-interchange.md) ·
[Changelog](../CHANGELOG.md) · [MIT](../LICENSE)
