#!/bin/sh
# build-parsey.sh DIR: build OpenBSD's ntpd parse.y, unchanged, with byacc, into
# DIR/parsey (a binary taking a config file and timing parse_config).
set -e
here="$(cd "$(dirname "$0")" && pwd)"
src=${NTPD_SRC:?NTPD_SRC (directory holding parse.y, ntpd.h, ...)}
d=$1
mkdir -p "$d"
(cd "$d" && byacc -d -o y.tab.c "$src/parse.y")
gcc -O2 -std=gnu11 -D_GNU_SOURCE -w -include "$here/shim/compat.h" \
	-I"$src" -I"$here/shim" -I/w/tests/bsdinc -I"$here/../drv" \
	"$d/y.tab.c" "$here/stubs.c" "$here/main-ntpd.c" -o "$d/parsey"
