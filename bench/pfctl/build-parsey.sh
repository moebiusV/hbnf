#!/bin/sh
# build-parsey.sh DIR: build OpenBSD's pfctl parse.y, unchanged, with byacc, into DIR/parsey.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
src=${PFCTL_SRC:?PFCTL_SRC (directory holding parse.y, sbin/pfctl/, sys/)}
d=$1; mkdir -p "$d"
(cd "$d" && byacc -d -o y.tab.c "$src/sbin/pfctl/parse.y")
gcc -O2 -std=gnu11 -D_GNU_SOURCE -w -include "$here/shim/compat.h" \
	-I"$here/shim" -I"$src/sbin/pfctl" -I"$src/sys" \
	"$d/y.tab.c" "$here/stubs.c" "$here/unused.c" "$here/main-pfctl.c" -o "$d/parsey"
