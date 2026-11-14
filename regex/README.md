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

[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/lisp/)

</div>

Add CL-PPCRE search and full-match operators to native queries. Needs
[`libtmux/query`](../query/README.md) and CL-PPCRE; never calls tmux.

[Documentation](https://libtmux.org/en/lisp/) · [Query API][api-query]

## Load it

Do the root [source setup](../README.md#install-from-source) first, with its
locked optional dependencies, then:

```lisp
(asdf:load-system "libtmux/regex")
```

## Match text with a regex

### [`libtmux.query:compile-filter`][api-compile-filter]: a regex filter, scanned once

[`libtmux.query:matching`][api-matching] applies it locally. The filter keeps
an owned copy of the pattern and prepares the scanner once.

- `:regex-search` matches anywhere in a text field.
- `:regex-full-match` matches the whole value.
- Both take `(:cl-ppcre pattern options...)`.

The examples share this package, where `tm` is `libtmux` and `q` is
`libtmux.query`:

<!-- example:package -->
```lisp
(defpackage #:libtmux.examples
  (:use #:cl)
  (:local-nicknames (#:tm #:libtmux)
                    (#:q #:libtmux.query)
                    (#:j #:libtmux.json)
                    (#:ws #:libtmux.workspace))
  (:export #:inspect-workspace #:create-workspace #:observed-value
           #:apply-workspace-document #:workspace-description
           #:terminate-owned-server #:configuration-report))

(in-package #:libtmux.examples)
```
<!-- /example -->

This selects `cat` panes with a case-insensitive full match. `snapshot` is an
acquired capture:

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

Run every example on a private daemon:

```console
$ mise run examples
```

More: [regex operators and modes](../docs/queries.md#add-optional-regex-operators) ·
[runnable program](../examples/workspace.lisp) ·
[REPL tutorial](../docs/tutorial.md)

## Limits

- **CL-PPCRE semantics.** tmux or another language's engine may read the same
  pattern differently.
- **Visit limits bound traversal.** They do not interrupt a scan already
  running.
- **A missing field fails the match.**
- **Exchange needs JSON.** Load [`libtmux/json`](../json/README.md) and pass
  `:allow-regex t` when decoding regex documents.

[Query API][api-query] · [Interchange](../docs/query-interchange.md) ·
[Changelog](../CHANGELOG.md) · [MIT](../LICENSE)

[api-compile-filter]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-compile-filter/
[api-matching]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-matching/
[api-query]: https://libtmux.org/en/lisp/latest/reference/libtmux-query/
