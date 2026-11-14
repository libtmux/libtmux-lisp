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

[Documentation](https://libtmux.org/en/lisp/) · [Query API][api-query]

## Load and use

Complete the root [source setup](../README.md#install-from-source), including
the locked optional dependencies, then load:

```lisp
(asdf:load-system "libtmux/regex")
```

Use `:regex-search` to find a match anywhere in a text field, or
`:regex-full-match` to match its complete value. Both declare the engine with
`(:cl-ppcre pattern options...)`.
[`libtmux.query:compile-filter`][api-compile-filter] retains an owned pattern
and prepares the scanner once.

This definition excerpt selects the demo's `cat` panes using an explicit
case-insensitive full match. The [runnable example](../examples/workspace.lisp)
defines the local nicknames `tm` for `libtmux` and `q` for `libtmux.query`;
`snapshot` is a previously acquired capture:

<!-- example:regex -->
```lisp
(defparameter *cat-command-filter*
  (q:compile-filter
   :pane
   '(:regex-full-match :pane/current-command
     (:cl-ppcre "CAT" :case-insensitive-mode t))))

(defun cat-pane-data (snapshot)
  "Return owned data for captured panes whose command is exactly cat; no I/O."
  (map 'vector #'tm:entity-data
       (q:matching *cat-command-filter* (tm:panes snapshot))))
```
<!-- /example -->

[`libtmux.query:matching`][api-matching] evaluates the compiled filter locally.
The [REPL tutorial](../docs/tutorial.md) supplies package setup and acquisition.

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
[Query API][api-query] ·
[Interchange](../docs/query-interchange.md) ·
[Changelog](../CHANGELOG.md) · [MIT](../LICENSE)

[api-compile-filter]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-compile-filter/
[api-matching]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-matching/
[api-query]: https://libtmux.org/en/lisp/latest/reference/libtmux-query/
