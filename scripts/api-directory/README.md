# api-directory

Reads a class docstring's capability directory the way the documentation site
does: three or more bold-led paragraphs, each followed by a paragraph of
references only, fold into a table. Text that misses the shape stays prose, so
a malformed directory would fail silently on the site.
`check-documentation-artifact` loads this file; it has no entry point.

Tests: `mise run scripts`.
