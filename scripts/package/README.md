# package

Builds `dist/libtmux-source.tar.gz`, a reproducible source archive, then loads
it as isolated consumers: the core system without the query, workspace, regex,
JSON or threading libraries; each optional system with only its own
dependencies; and the workspace command line. With `--examples` it also runs
the integration suites, the documentation check and the examples from the
extracted tree. CI runs both forms.

```console
$ mise run package
```

```console
$ mise run package-examples
```

Evidence goes to `dist/package-evidence.json`. Tests: `mise run scripts`.
