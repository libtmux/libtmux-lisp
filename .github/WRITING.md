# Writing

Lead with the conclusion or observable behavior, then give the evidence needed
to assess it. Use active voice, concrete nouns, and short sentences. Assume
the reader has no conversation history; explain what an issue or commit is
about instead of citing only its identifier.

Document what exists. Distinguish scaffolding, implemented behavior, tested
behavior, and a published release. Remove filler, promotional claims, emojis,
personal information, and machine-specific paths. Keep comments that explain
a non-obvious constraint; remove narration of the next line.

Describe the caller's task before implementation details. Explain defaults,
errors, side effects, ownership, ordering, and concurrency when they affect
the contract. Keep examples aligned with available APIs and show required
setup and cleanup. Once executable examples exist, quote their tested source
instead of maintaining a second copy.

Keep the README focused on purpose, truthful installation, a useful native
workflow and routes to the guides. Preserve its task/navigation table when
adding examples. Put detailed contracts in their owning guide. Link the first
useful prose mention of a library symbol to its actual reference anchor; use
Common Lisp package and call syntax. Keep links out of executable code fences.

Repository links stay relative. Use a published package or hosted reference
only when it exists, and check that it reaches the intended symbol and version.
Registry installation and source-checkout setup are different reader paths.
Do not invent a package release, documentation deployment or capability badge.

Shared conventions govern observable behavior, evidence and terminology.
Keep Common Lisp's API, ASDF systems, FiveAM workflow and documentation layout.
An open or closed-unmerged proposal is not an accepted cross-port rule.

## Native documentation

Public functions, macros, classes and conditions carry real Lisp documentation.
Make the first sentence useful on its own in REPL help. Explain arguments,
return values and multiple values, absence, ownership, ordering, I/O, blocking,
errors and stale-target behavior where they affect callers. Keep signatures
and method applicability in generated references rather than duplicating them
by hand. Package documentation explains package-wide contracts; ASDF component
descriptions identify module responsibilities.

Use Lisp docstring conventions and actual exported symbols. Describe CLOS
objects, sequence inputs and conditions through their native contracts.
Similar names across ports require their own semantic evidence. Document only
tested implementation/platform combinations.

## Executable examples

A complete program shows loading/package setup, inputs, an entry point, its
run command and an observable result. Do not require hidden aliases, variables
or a fixture imported from the test suite. A function excerpt may stay a
function excerpt when labelled as such and linked to its runnable setup.

Edit the executable source behind an excerpt. Source matching, compilation and
execution are different checks: run the displayed setup and program, assert
the claimed behavior, and verify cleanup. Changing a displayed alias, argument
or command needs execution evidence. Run shipped examples from the extracted
artifact too; successful source-tree loading does not establish consumer use.

Choose an explicit owned endpoint for runnable examples. An owned fixture may
terminate its daemon; a borrowed client releases only its own resources.
Distinguish command completion, application readiness and input consumption.
State feature-specific requirements and keep unsupported examples out of the
first-use path. Do not equate a smoke check with full compatibility or a test
duration with a performance benchmark.

Keep example IDs and extraction markers stable. Preserve directives and
generated-source markers when trimming comments. Imported source follows this
port's native formatting; a sibling's proposed formatter or harness is not a
reason to replace working Lisp tooling.

These practices follow the shared
[documented-example policy](https://github.com/libtmux/docs/blob/ff7b2e484b4503e599dc83c212ffd21f14c35dbe/WRITING.md#documented-examples-that-run)
and accepted [packed-consumer example checks](https://github.com/libtmux/libtmux-elixir/pull/14).

## Errors and comments

Error messages name the failed operation, its immediate cause, and a useful
next action. Performance claims need a measurement and a reproduction command.

Keep source comments only when they preserve a non-obvious invariant, protocol
constraint, ordering requirement or upstream quirk. Delete narration of the
next line, duplicated defaults, speculative work and history already in Git.
Keep rationale and rejected alternatives in the commit message.

## Markdown

Use descriptive links, a blank line before lists, and a blank line after
headings. Wrap repository prose at 80 columns where practical without breaking
URLs, identifiers, or tables.

Code blocks are paste-and-run units:

- Put one command in each block; explicit chaining or continuation counts as
  one command.
- Put explanations and comments outside the fence.
- Use `console` with a `$ ` prefix for shell commands.
- Split long commands with `\`, one flag or flag-value pair per continuation
  line.
- Use the source language tag for code examples and verify examples as shown.

## Commit messages

Use this format, with a lowercase scope unless it is a proper name:

```text
scope(type[detail]) Concise description

why: Explain the necessity or impact.
what:
- State the concrete change
- Keep the commit focused on one topic
```

Common types include `feat`, `fix`, `refactor`, `docs`, `chore`, and `test`.
Explain what changed and why it matters. Keep temporary validation results in
the review discussion. Do not add emojis or agent attribution.
