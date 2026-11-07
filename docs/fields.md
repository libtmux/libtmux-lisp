# Captured fields

Generated from registry version 1 by `mise run docs`.

Use `field-value` with a captured entity and one keyword below. It returns
value and presence as two values. Present false is `nil, t`; absence is
`nil, nil`. Text and relation containers are copied. All access is local.
An unknown field or unloaded relation signals `field-unavailable`.

[Graph and ownership](captures.md) · [API](api.md#field-value-function)

## SESSION

| Field | Type | Presence / relation |
| --- | --- | --- |
| `:SESSION/ATTACHED-COUNT` | Integer 0…4294967295 | Present |
| `:SESSION/CLIENTS` | MANY CLIENT | Captured target(s) |
| `:SESSION/CREATED` | Integer -9223372036854775808…9223372036854775807 | Optional |
| `:SESSION/ID` | String | Present |
| `:SESSION/NAME` | String | Present |
| `:SESSION/WINDOW-LINK-COUNT` | Integer 0…4294967295 | Present |
| `:SESSION/WINDOW-LINKS` | MANY WINDOW-LINK | Captured target(s) |

## WINDOW

| Field | Type | Presence / relation |
| --- | --- | --- |
| `:WINDOW/HEIGHT` | Integer 1…4294967295 | Present |
| `:WINDOW/ID` | String | Present |
| `:WINDOW/LAYOUT` | String | Optional |
| `:WINDOW/LINKS` | MANY WINDOW-LINK | Captured target(s) |
| `:WINDOW/NAME` | String | Present |
| `:WINDOW/PANE-COUNT` | Integer 0…4294967295 | Present |
| `:WINDOW/PANES` | MANY PANE | Captured target(s) |
| `:WINDOW/WIDTH` | Integer 1…4294967295 | Present |

## PANE

| Field | Type | Presence / relation |
| --- | --- | --- |
| `:PANE/ACTIVE` | Boolean | Present |
| `:PANE/CURRENT-COMMAND` | String | Optional |
| `:PANE/CURRENT-PATH` | String | Optional |
| `:PANE/DEAD` | Boolean | Present |
| `:PANE/HEIGHT` | Integer 1…4294967295 | Present |
| `:PANE/ID` | String | Present |
| `:PANE/INDEX` | Integer 0…4294967295 | Present |
| `:PANE/PID` | Integer 1…2147483647 | Optional |
| `:PANE/START-COMMAND` | String | Present |
| `:PANE/TITLE` | String | Present |
| `:PANE/WIDTH` | Integer 1…4294967295 | Present |
| `:PANE/WINDOW` | ONE WINDOW | Captured target(s) |

## WINDOW-LINK

| Field | Type | Presence / relation |
| --- | --- | --- |
| `:LINK/ACTIVE` | Boolean | Present |
| `:LINK/INDEX` | Integer 0…2147483647 | Present |
| `:LINK/SESSION` | ONE SESSION | Captured target(s) |
| `:LINK/WINDOW` | ONE WINDOW | Captured target(s) |

## CLIENT

| Field | Type | Presence / relation |
| --- | --- | --- |
| `:CLIENT/CONTROL-MODE` | Boolean | Present |
| `:CLIENT/CREATED` | Integer -9223372036854775808…9223372036854775807 | Optional |
| `:CLIENT/NAME` | String | Present |
| `:CLIENT/PID` | Integer 1…2147483647 | Present |
| `:CLIENT/READ-ONLY` | Boolean | Present |
| `:CLIENT/SESSION` | ONE SESSION | Captured target(s) |
| `:CLIENT/TTY` | String | Optional |

`:CLIENT` is the attached-client model, not the connection client.
Optional integer `:pane/pid` treats tmux's zero as absence. Optional text
treats an empty wire value as absence. Session creation time may be absent.
Names and titles retain present empty strings. See [capture semantics](captures.md).
