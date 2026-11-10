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

## Load and use

Complete the root [source setup](../README.md#install-from-source), then load
the system in your application:

```lisp
(asdf:load-system "libtmux/query")
```

Use `loop`, `map`, `reduce` and other ordinary sequence operations on captured
objects. For reusable declarations,
[`compile-filter`](../docs/query-api.md#compile-filter-function) validates a
keyword-headed form and returns an inspectable filter;
[`predicate`](../docs/query-api.md#predicate-function) returns a Lisp function.
[`matching`](../docs/query-api.md#matching-function) accepts lists or vectors
and returns a fresh simple vector, preserving order and duplicate entries.

Start with the [native query example](../README.md#compile-a-local-query) and
the [REPL tutorial](../docs/tutorial.md#select-and-project-locally). Their
definitions come from [the runnable example](../examples/workspace.lisp);
the [example runner](../examples/run.lisp) checks native and compiled results
against the same captured graph.

From the checkout root, run the programs with their owned daemon fixtures:

```console
$ mise run examples
```

## Contracts and extensions

Filtering, relationship traversal and inspection read retained observations.
They do not acquire or refresh tmux state. Empty results are `#()`;
[`one-or-none`](../docs/query-api.md#one-or-none-function) uses a second return
value for presence. Declarative filters target the registered captured models;
application-specific objects use ordinary function predicates.

Read [query semantics and limits](../docs/queries.md), the
[API reference](../docs/query-api.md), optional [regex](../regex/README.md) and
[JSON](../json/README.md) integrations. These systems share the root
[changelog](../CHANGELOG.md) and [MIT license](../LICENSE).
