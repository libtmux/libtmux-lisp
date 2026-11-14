<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="../docs/assets/logo.svg" type="image/svg+xml">
    <img src="../docs/assets/logo-512.png" width="128" height="128" alt="libtmux for Common Lisp">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# libtmux/json

[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/lisp/)

</div>

Read and write bounded `libtmux.lisp.filter/1` query documents. This optional
ASDF system depends on [`libtmux/query`](../query/README.md) and Jzon. It
performs no tmux I/O and does not open or close application files.

[Documentation](https://libtmux.org/en/lisp/) · [JSON API][api-json]

## Load and use

Complete the root [source setup](../README.md#install-from-source), including
the locked optional dependencies, then load:

```lisp
(asdf:load-system "libtmux/json")
```

[`libtmux.json:write-filter`][api-write-filter] returns a fresh JSON
string, or writes to a caller-owned character stream.
[`libtmux.json:read-filter`][api-read-filter] validates one complete
string and returns a compiled native filter.

This example also uses a regex filter, so load the optional regex system:

```lisp
(asdf:load-system "libtmux/regex")
```

These definition excerpts from the [runnable example](../examples/workspace.lisp)
compile a filter, serialize it, restore it with explicit regex permission and
match the same captured snapshot. That program defines the local nicknames
`tm` for `libtmux`, `q` for `libtmux.query` and `j` for `libtmux.json`:

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

<!-- example:filterdocument -->
```lisp
(defun round-trip-filter-document (snapshot)
  "Round-trip the checked regex filter and apply it to one retained snapshot."
  (let* ((document (j:write-filter *cat-command-filter*))
         (restored (j:read-filter document :allow-regex t)))
    (values document
            (map 'vector #'tm:entity-data
                 (q:matching restored (tm:panes snapshot))))))
```
<!-- /example -->

`round-trip-filter-document` returns the JSON string and a vector of pane data.
The [REPL tutorial](../docs/tutorial.md) supplies package setup and acquisition.

Run the complete example from the checkout root:

```console
$ mise run examples
```

## Document boundary

Boolean false, empty membership arrays and missing members remain distinct.
The current schema has no nullable operands. Unknown or duplicate properties,
unknown registry names and exhausted parsing limits signal typed conditions.
Decoding never evaluates Lisp or interns external names.

Regex documents require [`libtmux/regex`](../regex/README.md) and explicit
`:allow-regex t`. Native closures cannot be serialized. This is the Common Lisp
port's schema; similar documents from another port require separate conformance
evidence. Workspace documents use
[`libtmux/workspace`](../workspace/README.md), not this query codec.

[Schema and limits](../docs/query-interchange.md) ·
[JSON API][api-json] · [Queries](../docs/queries.md) ·
[Changelog](../CHANGELOG.md) · [MIT](../LICENSE)

[api-json]: https://libtmux.org/en/lisp/latest/reference/libtmux-json/
[api-read-filter]: https://libtmux.org/en/lisp/latest/reference/libtmux-json-read-filter/
[api-write-filter]: https://libtmux.org/en/lisp/latest/reference/libtmux-json-write-filter/
