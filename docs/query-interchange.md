# Optional query interchange

`libtmux/regex` and `libtmux/json` are separate ASDF systems. Core and
`libtmux/query` remain loadable with Common Lisp plus ASDF/UIOP. The optional
systems add CL-PPCRE and Jzon only where their behavior is required.

[Query guide](queries.md) · [Query API](query-api.md) ·
[JSON API](json-api.md) · [Testing](testing.md)

## Load only what the application uses

Enable the two regex operators:

```lisp
(asdf:load-system "libtmux/regex")
```

Enable versioned JSON reading and writing:

```lisp
(asdf:load-system "libtmux/json")
```

Load both before reading a document containing regex nodes. Neither system
contacts tmux.

## Compile a reusable regex

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

The compiled filter retains owned pattern/options data and one prepared
CL-PPCRE scanner. `:regex-search` accepts a match anywhere;
`:regex-full-match` requires the complete captured string. An absent field does
not match. Parser and query visit limits do not interrupt scanner execution.

## Round-trip a compiled filter

Applications can give `libtmux.json` a package-local nickname such as `j`.
Writing returns a fresh string by default:

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

Without `:allow-regex t`, `read-filter` rejects a regex node before compiling
its scanner. Non-regex documents need only `libtmux/json`.

`write-filter` returns a fresh string unless given an open output character
stream. It does not open pathnames or close a caller-owned stream.

## Wire envelope

The native schema is `libtmux.lisp.filter/1`:

```json
{"schema":"libtmux.lisp.filter/1","model":"pane","registryVersion":1,"expression":["and",["=","pane/active",false],["in","pane/current-command",[]]]}
```

The root object is closed and requires exactly the named members. Duplicate or
unknown members, unknown models/operators/fields, wrong arities and unsupported
registry versions signal `invalid-filter-document`. External names remain
strings until allowlist lookup; the decoder never interns them.

Boolean false is JSON `false`. An empty membership is `[]`. JSON `null` is
distinct and rejected because registry version 1 has no nullable query operand.
Numeric operands are integers; decimal and exponent syntax is rejected before
Jzon converts the token.
Native closures and QuerySet callbacks are not serializable recipes.

This schema belongs to the Common Lisp port. Similar JSON from another port is
not compatible without operator-by-operator conformance evidence.

## Decoder limits

`read-filter` accepts one complete JSON string and defaults to:

| Limit | Default |
| --- | ---: |
| UTF-8 input | 1 MiB |
| Nesting depth | 64 |
| JSON nodes | 10,000 |
| One string | 65,536 characters |
| Membership operands | 1,000 |
| Decimal digits in one numeric token | 128 |

Override a limit with the corresponding keyword argument. An exhausted bound
signals `filter-document-limit-exceeded`; `document-limit` identifies the
bound and `document-path` returns an owned location vector. Jzon syntax failures
and native-query validation failures remain available through `error-cause`.
