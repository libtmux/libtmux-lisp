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

Error messages name the failed operation, its immediate cause, and a useful
next action. Performance claims need a measurement and a reproduction command.

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
