# Native scalar queries

`libtmux/query` compiles inert keyword-headed data into a reusable Common Lisp
function over captured entities. Compilation and evaluation are local: they do
not acquire, refresh or mutate tmux. Use an ordinary Lisp function when a
one-off selection does not need validation or inspection.

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

Relation operators and QuerySet are not part of the scalar system yet. `:any`,
`:all`, `:none` and `:is` fail explicitly until `libtmux/query` gains the
relation implementation. Regex operators belong to the later optional
`libtmux/regex` system.

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
execution scope to 1,000,000 node visits. `compile-filter`, `matching`, `one`
and `one-or-none` expose narrower keyword limits for untrusted in-process data.

Cycles, dotted lists, invalid operators, wrong field types and unavailable
optional systems signal `invalid-filter`. Limit exhaustion signals its subtype
`query-limit-exceeded`. Applying a compiled filter to the wrong captured model
or to a plist signals `invalid-query-target`. Diagnostics retain bounded type
and path data; they do not print an unbounded caller object.

External configuration files need the later bounded JSON codec. Disabling
`*read-eval*` alone does not turn the Common Lisp reader into a query parser.
