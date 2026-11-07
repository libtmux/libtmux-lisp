# Query JSON API

Generated from live package documentation and signatures by `mise run docs`.
Edit source docstrings; `mise run check` detects drift.

[Interchange guide](query-interchange.md) · [Query guide](queries.md)

Bounded JSON interchange for native libtmux query filters.
READ-FILTER accepts a complete JSON string in schema libtmux.lisp.filter/1.
It resolves only registered names, rejects duplicate or unknown members, and
never evaluates input as Lisp code. WRITE-FILTER serializes only compiled
declarative filters; native function predicates are not query documents.

## Functions

<a id="document-limit-function"></a>

### document-limit

`(document-limit condition)`

Return the exhausted document limit name, or NIL.

[Source](../src/json.lisp)

<a id="document-path-function"></a>

### document-path

`(document-path condition)`

Return a fresh vector locating a filter-document error.

[Source](../src/json.lisp)

<a id="read-filter-function"></a>

### read-filter

`(read-filter source &key (allow-regex nil) (max-input-bytes +default-max-input-bytes+) (max-depth +default-max-depth+) (max-nodes +default-max-nodes+) (max-string-length +default-max-string-length+) (max-membership +default-max-membership+) (max-integer-digits +default-max-integer-digits+))`

Read one bounded libtmux.lisp.filter/1 JSON string into a compiled filter.
External names resolve through closed registries and are never interned. Regex
nodes are rejected unless ALLOW-REGEX is true and libtmux/regex is loaded.
Parser limits bound UTF-8 input bytes, nesting, JSON nodes, strings, membership
arrays and integer-token digits. Decimal and exponent number syntax is rejected
before conversion. Parser limits do not interrupt CL-PPCRE execution.

[Source](../src/json.lisp)

<a id="write-filter-function"></a>

### write-filter

`(write-filter filter &key stream (pretty nil))`

Serialize a COMPILED-FILTER as one libtmux.lisp.filter/1 JSON document.
Return a fresh string when STREAM is NIL; otherwise write to the supplied open
output character stream and return NIL without closing it. Pathnames and binary
streams are rejected. The wire contract is native to this port and does not
imply cross-port regex or query equivalence.

[Source](../src/json.lisp)

## Conditions

These types retain bounded document diagnostics; their slots are private.

<a id="filter-document-limit-exceeded-type"></a>

### filter-document-limit-exceeded

A filter document exceeds a configured parsing or query-data limit.

[Source](../src/json.lisp)

Direct supertypes: `invalid-filter-document`.

<a id="invalid-filter-document-type"></a>

### invalid-filter-document

A filter document is malformed, unknown, or semantically invalid.

[Source](../src/json.lisp)

Direct supertypes: `libtmux-error`.
