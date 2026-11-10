# Native queries

`libtmux/query` compiles inert keyword-headed data into a reusable Common Lisp
function over captured entities and their registered relationships. Compilation
and evaluation are local: they do not acquire, refresh or mutate tmux. Use an
ordinary Lisp function when a one-off selection does not need validation or
inspection.

[Query API](query-api.md) · [Captured fields](fields.md) ·
[Runnable tutorial](tutorial.md#select-and-project-locally)

## Load without global nicknames

Load the separate query system. It loads `libtmux` but no regex, JSON or thread
library:

```lisp
(asdf:load-system "libtmux/query")
```

Applications can choose package-local nicknames:

```lisp
(defpackage #:my-tmux-tool
  (:use #:cl)
  (:local-nicknames (#:tm #:libtmux)
                    (#:q #:libtmux.query)))

(in-package #:my-tmux-tool)
```

The library does not claim the short global package names `tm` or `q`.

## Compile once and match locally

Quoted lists are data. `compile-filter` validates the root model, operator,
field, arity and operand types; it never calls `eval`.

```lisp
(defparameter *editors*
  (q:compile-filter
   :pane
   '(:and
     (:= :pane/active t)
     (:in :pane/current-command ("nvim" "vim"))
     (:>= :pane/width 100))))
```

Use the returned genuine function with standard sequence operations:

```lisp
(remove-if (complement (q:predicate *editors*)) panes)
```

Or request a fresh simple vector with original order and multiplicity:

```lisp
(q:matching *editors* panes)
```

`matching` accepts a proper finite list or a non-string vector. It honors fill
pointers and displaced vectors, validates the complete outer container before
evaluation, and shares one execution budget across the traversal. It retains
the captured handles; it does not copy the object graph.

## Scalar semantics

| Form | Fields | Meaning |
| --- | --- | --- |
| `(:= field value)` | Text, integer, Boolean | Typed equality |
| `(:< field n)`, `(:<= field n)`, `(:> field n)`, `(:>= field n)` | Integer | Mathematical integer comparison |
| `(:in field values)` | Text, integer, Boolean | Typed finite membership |
| `(:contains field text)` | Text | Case-sensitive substring search |
| `(:starts-with field text)` | Text | Case-sensitive prefix |
| `(:and ...)`, `(:or ...)`, `(:not expression)` | Expressions | Ordered Boolean composition |
| `(:present field)`, `(:missing field)` | Scalar | Captured presence |

Text uses content comparison. Integers are Common Lisp integers; wire-decoding
bounds do not truncate query operands. Ratios and floats are invalid. Empty AND
is true, empty OR and empty membership are false. A bare `nil` filter is
invalid.

Presence is separate from truth. `(:= :pane/active nil)` compares a present
false value. A scalar comparison on an absent optional field is false, so NOT
of that comparison is true. Use `:present` when absence must be excluded.
Missing required capture data signals `field-unavailable`.

## Add optional regex operators

Load CL-PPCRE support without changing the dependency boundary of core or
`libtmux/query`:

```lisp
(asdf:load-system "libtmux/regex")
```

The operand is owned declarative data: the engine, pattern and closed scanner
options. Search and full match are separate operations:

```lisp
(q:compile-filter
 :pane
 '(:regex-search :pane/current-command
   (:cl-ppcre "^(n?vim)$" :case-insensitive-mode t)))
```

Supported Boolean options are `:case-insensitive-mode`, `:multi-line-mode`,
`:single-line-mode` and `:extended-mode`. The scanner is compiled once. A match
at position zero is true. An absent optional text field is false. Query visit
limits do not interrupt CL-PPCRE scanner execution; use regex only with trusted
local patterns and inputs appropriate to that engine.

The separate [query interchange guide](query-interchange.md) shows bounded JSON
round trips and the explicit regex read opt-in.

## Traverse captured relationships

Relation forms compile their child expression for the registered target model:

| Form | Relation | Empty or missing behavior |
| --- | --- | --- |
| `(:any relation expression)` | To-many | False on an empty relation |
| `(:all relation expression)` | To-many | True on an empty relation |
| `(:none relation expression)` | To-many | True on an empty relation |
| `(:is relation expression)` | To-one | False when the target is absent |

This expression requires one pane to be both active and running `nvim`:

```lisp
(q:compile-filter
 :session
 '(:any :session/window-links
   (:is :link/window
    (:any :window/panes
     (:and (:= :pane/active t)
           (:= :pane/current-command "nvim"))))))
```

Two separate `:any` forms may match different panes. Missing or unloaded
relationship data signals `field-unavailable`; it is not treated as a known
empty collection. `required-relations` reports every traversed relation in
first-occurrence order.

## Keep eager local selections in a QuerySet

QuerySet is an optional collection convenience, not a replacement for Common
Lisp sequences. It owns a simple-vector container and remains eager:

```lisp
(let* ((all (q:from panes :model :pane))
       (editors (q:where all *editors*))
       (wide (q:where-if editors (lambda (pane) (>= (tm:width pane) 120))))
       (ordered (q:order-by wide #'> :key #'tm:width)))
  (q:items ordered))
```

[`from`](query-api.md#from-function), [`where`](query-api.md#where-function),
[`where-if`](query-api.md#where-if-function) and
[`order-by`](query-api.md#order-by-function) return new objects.
[`items`](query-api.md#items-function) returns a fresh simple vector.
`order-by` uses `stable-sort` on a private copy, so equal
keys retain input order; its predicate and key follow Common Lisp's ordinary
sorting callback contract. Both operations accept function objects or symbols
naming global functions. They resolve each designator once before traversal or
sorting, so a redefinition during a call affects the next operation. Macros,
special operators and unbound function names signal
[`invalid-argument`](api.md#invalid-argument-type).
`where-if` calls its native function once per item in input order on normal
completion. A declared model is checked against every item; an empty
QuerySet can carry its model explicitly, while `where` can take the model from
its compiled filter. `one` and `one-or-none` accept QuerySets directly.

## Inspect owned query data

Inspection returns fresh ordinary data:

```lisp
(q:expression *editors*)
```

```lisp
(q:required-fields *editors*)
```

```lisp
(q:explain *editors*)
```

Changing the source form after compilation, or changing an inspection result,
does not alter the compiled filter. `fields` returns fresh registry metadata for
one of `:session`, `:window`, `:pane`, `:window-link` or `:client`. Here
`:client` means a captured attached tmux client, not the connection object.

[`explain`](query-api.md#explain-function) reports `:execution :local` and
`:source-filtering :unavailable`. Acquisition does not execute query filters.
The [source-execution decision](adr/0001-native-common-lisp-engine.md#qualify-control-mode-and-source-filtering-before-exposing-them)
records the relationship and native-evaluation guarantees still required.

## Select strictly before mutation

`one` requires exactly one item. `one-or-none` returns two values so an empty
selection differs from a singleton containing `nil`:

```lisp
(multiple-value-bind (pane present-p)
    (q:one-or-none (q:matching *editors* panes))
  (when present-p
    (tm:capture-pane client pane)))
```

Both functions validate the complete bounded input before returning a
candidate. Zero items signal `no-match` from `one`; multiple positions signal
`ambiguous-match`. Repeated references count as repeated positions. The
condition reports whether its count is exact and exposes a fresh bounded sample.
This ordering prevents a dependent mutation from running before uniqueness is
established.

## Resource limits and failures

The defaults bound nesting to 64 containers, compilation to 10,000 structure
visits, one membership to 1,000 values, one string to 65,536 characters,
retained query text to 1,048,576 characters, selection to 100,000 items and one
execution scope to 1,000,000 expression and relation visits. `compile-filter`,
`matching`, QuerySet constructors, `one` and `one-or-none` expose narrower
keyword limits for untrusted in-process data.

Cycles, dotted lists, invalid operators, wrong field types and unavailable
optional systems signal `invalid-filter`. Limit exhaustion signals its subtype
`query-limit-exceeded`. Applying a compiled filter to the wrong captured model
or to a plist signals `invalid-query-target`. Diagnostics retain bounded type
and path data; they do not print an unbounded caller object.

External configuration files need the later bounded JSON codec. Disabling
`*read-eval*` alone does not turn the Common Lisp reader into a query parser.
