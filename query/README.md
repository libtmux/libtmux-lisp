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

</div>

Filter captured tmux objects with ordinary Lisp predicates, validated query
data and eager QuerySets. This ASDF system depends on core `libtmux`; it adds
no external dependency and performs no tmux I/O.

[Documentation](https://libtmux.org/en/lisp/) · [Query API][api-query]

## Load and use

Complete the root [source setup](../README.md#install-from-source), then load
the system in your application:

```lisp
(asdf:load-system "libtmux/query")
```

Use `loop`, `map`, `reduce` and other ordinary sequence operations on captured
objects. For reusable declarations,
[`libtmux.query:compile-filter`][api-compile-filter] validates a
keyword-headed form and returns an inspectable filter;
[`libtmux.query:predicate`][api-predicate] returns a Lisp function.
[`libtmux.query:matching`][api-matching] accepts lists or vectors
and returns a fresh simple vector, preserving order and duplicate entries.

This definition excerpt selects active panes at least 40 cells wide from a
captured snapshot. The [runnable example](../examples/workspace.lisp) defines
the local nicknames `tm` for `libtmux` and `q` for `libtmux.query`:

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

The [example runner](../examples/run.lisp) checks native and compiled results
against the same captured graph. The
[REPL tutorial](../docs/tutorial.md#select-and-project-locally) supplies loading,
package setup and snapshot acquisition.

From the checkout root, run the programs with their owned daemon fixtures:

```console
$ mise run examples
```

## Contracts and extensions

Filtering, relationship traversal and inspection read retained observations.
They do not acquire or refresh tmux state. Empty results are `#()`;
[`libtmux.query:one-or-none`][api-one-or-none] uses a second return
value for presence. Declarative filters target the registered captured models;
application-specific objects use ordinary function predicates.

Read [query semantics and limits](../docs/queries.md), the
[API reference][api-query], optional [regex](../regex/README.md) and
[JSON](../json/README.md) integrations. These systems share the root
[changelog](../CHANGELOG.md) and [MIT license](../LICENSE).

[api-compile-filter]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-compile-filter/
[api-matching]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-matching/
[api-one-or-none]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-one-or-none/
[api-predicate]: https://libtmux.org/en/lisp/latest/reference/libtmux-query-predicate/
[api-query]: https://libtmux.org/en/lisp/latest/reference/libtmux-query/
