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

</div>

Read and write bounded `libtmux.lisp.filter/1` query documents. This optional
ASDF system depends on [`libtmux/query`](../query/README.md) and Jzon. It
performs no tmux I/O and does not open or close application files.

## Load and use

Complete the root [source setup](../README.md#install-from-source), including
the locked optional dependencies, then load:

```lisp
(asdf:load-system "libtmux/json")
```

[`write-filter`](../docs/json-api.md#write-filter-function) returns a fresh JSON
string, or writes to a caller-owned character stream.
[`read-filter`](../docs/json-api.md#read-filter-function) validates one complete
string and returns a compiled native filter. See the
[round-trip example](../docs/query-interchange.md#round-trip-a-compiled-filter)
for serialization followed by local matching against the same capture.

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
[JSON API](../docs/json-api.md) · [Queries](../docs/queries.md) ·
[Changelog](../CHANGELOG.md) · [MIT](../LICENSE)
