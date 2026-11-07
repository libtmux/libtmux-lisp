#!/bin/sh
set -eu
: "${LIBTMUX_ASDF:=$(mise where http:asdf-lisp)/asdf.lisp}"
exec sbcl \
  --noinform \
  --no-sysinit \
  --no-userinit \
  --load "$LIBTMUX_ASDF" \
  --load .qlot/setup.lisp \
  --script "$@"
