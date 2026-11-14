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

Save and restore query filters as bounded `libtmux.lisp.filter/1` JSON.
Needs [`libtmux/query`](../query/README.md) and Jzon; never calls tmux.

[Documentation](https://libtmux.org/en/lisp/) · [JSON API][api-json]

## Load it

Do the root [source setup](../README.md#install-from-source) first, with its
locked optional dependencies, then:

```lisp
(asdf:load-system "libtmux/json")
```

## Save and restore a filter

### [`libtmux.json:write-filter`][api-write-filter]: a filter as JSON

Returns a fresh string, or writes to a character stream you own.

This example filters on a regex, so load the regex system too:

```lisp
(asdf:load-system "libtmux/regex")
```

These excerpts come from the [runnable program](../examples/workspace.lisp).
They share this package, where `tm` is `libtmux`, `q` is `libtmux.query` and
`j` is `libtmux.json`:

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

### [`libtmux.json:read-filter`][api-read-filter]: JSON back to a filter

Validates one complete string and returns a compiled filter. Regex documents
need `:allow-regex t`.

`round-trip-filter-document` returns the JSON string and a vector of pane data:

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

Run every example on a private daemon:

```console
$ mise run examples
```

More: [schema and limits](../docs/query-interchange.md) ·
[REPL tutorial](../docs/tutorial.md)

## Limits

- **Absence stays absence.** `false`, empty membership arrays and missing
  members stay distinct. The schema has no nullable operands.
- **Bad input signals typed conditions.** That covers unknown or duplicate
  properties, unknown registry names and exhausted parsing limits.
- **No evaluation.** Decoding never evaluates Lisp or interns external names.
- **No files.** It reads and writes strings and streams, never opens files.
- **No closures.** Native predicates cannot be serialized. Regex documents need
  [`libtmux/regex`](../regex/README.md).
- **Queries only.** Workspace documents belong to
  [`libtmux/workspace`](../workspace/README.md).
- **This port's schema.** Documents from another port are not promised to
  match.

[JSON API][api-json] · [Queries](../docs/queries.md) ·
[Changelog](../CHANGELOG.md) · [MIT](../LICENSE)

[api-json]: https://libtmux.org/en/lisp/latest/reference/libtmux-json/
[api-read-filter]: https://libtmux.org/en/lisp/latest/reference/libtmux-json-read-filter/
[api-write-filter]: https://libtmux.org/en/lisp/latest/reference/libtmux-json-write-filter/
