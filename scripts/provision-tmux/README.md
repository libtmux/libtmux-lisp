# provision-tmux

Builds one pinned tmux release for CI: it downloads the source archive named in
`tools/tmux-sources.json` with `curl`, checks its SHA-256, builds it with the
host toolchain and records provenance under the output directory. The
`.github/actions/build-tmux` action runs it, caches the result and then uses
the binary.

```console
$ mise exec -- sbcl --script scripts/provision-tmux/provision-tmux.lisp \
    --manifest tools/tmux-sources.json \
    --version 3.8 \
    --output-dir build/tmux \
    --cache-dir .cache/tmux
```

`--print-cache-key` prints the cache key without building; `--reuse` keeps a
matching earlier build. This port keeps its own recipe, with byacc and a
commit-pinned manifest, because the shared `libtmux/.github` build-tmux action
builds release archives with bison and does not read this manifest. Its
`apt-get` step uses the shared action. Tests: `mise run scripts`.
