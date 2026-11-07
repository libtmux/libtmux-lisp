# Native query API

Generated from live package documentation, signatures and operator metadata by
`mise run docs`. Edit source docstrings and the operator registry; `mise run
check` detects drift.

[Query guide](queries.md) · [Captured fields](fields.md) · [Core API](api.md)

Validated native queries over finite captured libtmux observations.
Loading this package adds no transport dependency and performs no tmux I/O.

## Functions

<a id="compile-filter-function"></a>

### compile-filter

`(compile-filter model form &key (max-depth +default-max-depth+) (max-input-visits +default-max-input-visits+) (max-membership +default-max-membership+) (max-string-length +default-max-string-length+) (max-retained-characters +default-max-retained-characters+) (max-execution-visits +default-max-execution-visits+))`

Compile FORM for captured MODEL into an owned local filter.
Scalar and registered relation operators perform no I/O and never evaluate
FORM as Lisp code. Regex operators require the optional regex system.
Keyword limits bound container depth, input visits, membership size, copied
character counts and later predicate execution. Limit failures signal
QUERY-LIMIT-EXCEEDED; malformed or mistyped forms signal INVALID-FILTER.

[Source](../src/query.lisp)

<a id="count-exact-p-function"></a>

### count-exact-p

`(count-exact-p condition)`

Return true when MATCH-COUNT is exact, false when it is a lower bound.

[Source](../src/query.lisp)

<a id="error-expected-function"></a>

### error-expected

`(error-expected condition)`

Return an owned bounded description of the expected query shape or type.

[Source](../src/query.lisp)

<a id="error-operator-function"></a>

### error-operator

`(error-operator condition)`

Return a bounded invalid-operator summary, or NIL.

[Source](../src/query.lisp)

<a id="error-path-function"></a>

### error-path

`(error-path condition)`

Return a fresh bounded vector locating the invalid query input.

[Source](../src/query.lisp)

<a id="error-received-function"></a>

### error-received

`(error-received condition)`

Return a safe bounded description of the received query value or target.

[Source](../src/query.lisp)

<a id="explain-function"></a>

### explain

`(explain filter)`

Return fresh execution metadata for FILTER. Query execution is local and acquires nothing.

[Source](../src/query.lisp)

<a id="expression-function"></a>

### expression

`(expression filter)`

Return a fresh ordinary-data copy of FILTER's canonical native expression.

[Source](../src/query.lisp)

<a id="fields-function"></a>

### fields

`(fields model)`

Return fresh field metadata for one captured query MODEL in key order.
MODEL is one of :SESSION, :WINDOW, :PANE, :WINDOW-LINK or :CLIENT. Wire bounds
describe capture decoding and do not restrict native query integer operands.

[Source](../src/query.lisp)

<a id="from-function"></a>

### from

`(from values &key model (max-items +default-max-selection-items+))`

Copy finite VALUES into an eager local QUERY-SET.
VALUES is a proper list, non-string vector or another query set. MODEL may name
one registered captured entity model; omit it for unrestricted ordinary data.

[Source](../src/query.lisp)

<a id="items-function"></a>

### items

`(items set)`

Return a fresh simple vector containing SET's selected items in order.

[Source](../src/query.lisp)

<a id="match-count-function"></a>

### match-count

`(match-count condition)`

Return the known cardinality associated with a selection condition.

[Source](../src/query.lisp)

<a id="match-sample-function"></a>

### match-sample

`(match-sample condition)`

Return a fresh bounded vector of safe selected-item summaries.

[Source](../src/query.lisp)

<a id="matching-function"></a>

### matching

`(matching filter values &key (max-items +default-max-selection-items+) max-execution-visits)`

Return a fresh simple vector of VALUES accepted by FILTER.
VALUES must be a finite list or non-string vector. The result preserves order,
multiplicity and the original captured handles. MAX-ITEMS bounds validation.
One execution budget is shared across the entire traversal; no I/O occurs.

[Source](../src/query.lisp)

<a id="one-function"></a>

### one

`(one values &key (max-items +default-max-selection-items+))`

Return the only item in finite VALUES.
Signal NO-MATCH for zero items or AMBIGUOUS-MATCH for more than one. The full
bounded container is validated before a candidate is returned. NIL is an item.

[Source](../src/query.lisp)

<a id="one-or-none-function"></a>

### one-or-none

`(one-or-none values &key (max-items +default-max-selection-items+))`

Return the only item and T, or NIL,NIL when finite VALUES is empty.
Signal AMBIGUOUS-MATCH for more than one item after validating the full bounded
container. A singleton containing NIL returns NIL,T.

[Source](../src/query.lisp)

<a id="order-by-function"></a>

### order-by

`(order-by set predicate &key (key (function identity)) (max-items +default-max-selection-items+))`

Return a new query set stably ordered by native PREDICATE and KEY.
Sorting mutates only a private simple-vector copy; SET remains unchanged.

[Source](../src/query.lisp)

<a id="predicate-function"></a>

### predicate

`(predicate filter)`

Return a genuine one-argument function that evaluates FILTER locally.
Each invocation receives a fresh execution budget and performs no tmux I/O.

[Source](../src/query.lisp)

<a id="query-set-model-function"></a>

### query-set-model

`(query-set-model set)`

Return SET's declared captured model, or NIL for untyped ordinary data.

[Source](../src/query.lisp)

<a id="required-fields-function"></a>

### required-fields

`(required-fields filter)`

Return a fresh vector of scalar fields in first-occurrence order.

[Source](../src/query.lisp)

<a id="required-relations-function"></a>

### required-relations

`(required-relations filter)`

Return a fresh vector of relation fields in first-occurrence order.

[Source](../src/query.lisp)

<a id="where-function"></a>

### where

`(where set filter &key (max-items +default-max-selection-items+) max-execution-visits)`

Return a new query set containing SET items accepted by compiled FILTER.
Evaluation is eager and local. FILTER supplies the result model; conflicting
declared model metadata signals INVALID-QUERY-TARGET before evaluation.

[Source](../src/query.lisp)

<a id="where-if-function"></a>

### where-if

`(where-if set function &key (max-items +default-max-selection-items+))`

Return a new query set selected by native FUNCTION in input order.
FUNCTION is called exactly once per item during this eager local traversal.
Its effects and call order are never optimized as declarative query data.

[Source](../src/query.lisp)

## Classes and conditions

These objects retain owned, bounded query state; their slots are private.

<a id="ambiguous-match-type"></a>

### ambiguous-match

Strict selection received more than one item.

[Source](../src/query.lisp)

Direct supertypes: `libtmux-error`.

<a id="compiled-filter-type"></a>

### compiled-filter

An owned validated expression and reusable local evaluator.

[Source](../src/query.lisp)

Direct supertypes: `standard-object`.

<a id="invalid-filter-type"></a>

### invalid-filter

A declarative filter is malformed, mistyped or exceeds a compile limit.

[Source](../src/query.lisp)

Direct supertypes: `libtmux-error`.

<a id="invalid-query-target-type"></a>

### invalid-query-target

A compiled filter received an object outside its captured root model.

[Source](../src/query.lisp)

Direct supertypes: `libtmux-error`.

<a id="no-match-type"></a>

### no-match

Strict selection received no items.

[Source](../src/query.lisp)

Direct supertypes: `libtmux-error`.

<a id="query-limit-exceeded-type"></a>

### query-limit-exceeded

A bounded query compilation, execution or selection exhausted its budget.

[Source](../src/query.lisp)

Direct supertypes: `invalid-filter`.

<a id="query-set-type"></a>

### query-set

An eager owned local selection with optional captured-model metadata.

[Source](../src/query.lisp)

Direct supertypes: `standard-object`.

## Operators

Scalar and relation rows are implemented locally. Regex operators require the
optional `libtmux/regex` system.

| Operator | Arity | Field kinds | Stage | Meaning |
| --- | ---: | --- | --- | --- |
| `:=` | 2 | `text`, `integer`, `boolean` | `scalar` | Typed equality |
| `:<` | 2 | `integer` | `scalar` | Integer less-than |
| `:<=` | 2 | `integer` | `scalar` | Integer less-than or equal |
| `:>` | 2 | `integer` | `scalar` | Integer greater-than |
| `:>=` | 2 | `integer` | `scalar` | Integer greater-than or equal |
| `:in` | 2 | `text`, `integer`, `boolean` | `scalar` | Typed finite membership |
| `:contains` | 2 | `text` | `scalar` | Case-sensitive substring search |
| `:starts-with` | 2 | `text` | `scalar` | Case-sensitive text prefix |
| `:and` | variadic |  | `scalar` | Ordered conjunction; empty is true |
| `:or` | variadic |  | `scalar` | Ordered disjunction; empty is false |
| `:not` | 1 |  | `scalar` | Boolean negation |
| `:present` | 1 | `text`, `integer`, `boolean` | `scalar` | Captured value is present |
| `:missing` | 1 | `text`, `integer`, `boolean` | `scalar` | Optional captured value is absent |
| `:any` | 2 | `relation` | `relations` | A related object matches |
| `:all` | 2 | `relation` | `relations` | Every related object matches |
| `:none` | 2 | `relation` | `relations` | No related object matches |
| `:is` | 2 | `relation` | `relations` | A to-one relation target matches |
| `:regex-search` | 2 | `text` | `regex` | CL-PPCRE search |
| `:regex-full-match` | 2 | `text` | `regex` | CL-PPCRE full match |
