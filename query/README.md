<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="../docs/assets/logo.svg" type="image/svg+xml">
    <img src="../docs/assets/logo-512.png" width="128" height="128" alt="libtmux for Common Lisp">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# libtmux/query

[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/lisp/)

</div>

Filter captured tmux objects with plain Lisp predicates or validated query
data. Needs only core `libtmux`; never calls tmux.

[Documentation](https://libtmux.org/en/lisp/) · [Query API][api-query]

## Load it

Do the root [source setup](../README.md#install-from-source) first, then:

```lisp
(asdf:load-system "libtmux/query")
```

## Filter captured objects

### [`libtmux.query:compile-filter`][api-compile-filter]: validate a filter once

[`libtmux.query:predicate`][api-predicate] returns the same filter as a Lisp
function. [`libtmux.query:matching`][api-matching] applies either to a list or
vector.

This selects active panes at least 40 cells wide. `tm` is `libtmux`, `q` is
`libtmux.query`, and `snapshot` is an acquired capture:

<!-- example:query -->
```lisp
(defparameter *wide-active-filter*
  (q:compile-filter
   :pane
   '(:and (:= :pane/active t)
          (:>= :pane/width 40))))

(defun wide-active-pane-data (snapshot)
  "Return owned data for captured active panes at least 40 cells wide; no I/O."
  (map 'vector #'tm:entity-data
       (q:matching *wide-active-filter* (tm:panes snapshot))))
```
<!-- /example -->

Run every example on a private daemon:

```console
$ mise run examples
```

- Results are a fresh simple vector, in order, duplicates kept.
- No match gives `#()`.
  [`libtmux.query:one-or-none`][api-one-or-none] reports presence as a second
  value.

More: [query guide](../docs/queries.md) ·
[runnable program](../examples/workspace.lisp) ·
[REPL tutorial](../docs/tutorial.md#select-and-project-locally)

## What it leaves out

- **tmux calls.** Filtering and relations read retained captures; they never
  refresh them.
- **Your own objects.** Declarative filters target the captured models; use a
  function predicate for anything else.

[Regex operators](../regex/README.md) · [JSON documents](../json/README.md) ·
[Changelog](../CHANGELOG.md) · [MIT](../LICENSE)

[api-compile-filter]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-compile-filter/
[api-matching]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-matching/
[api-one-or-none]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-one-or-none/
[api-predicate]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-predicate/
[api-query]: https://libtmux.org/en/lisp/latest/reference/libtmux-query/
