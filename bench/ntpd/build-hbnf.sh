#!/bin/sh
# build-hbnf.sh DIR: build hbnf's ntpd binding (grammars/bind/ntpd.hbnf, --conf)
# against the same ntpd.h, stubs and main as the byacc build, into DIR/hbnfd.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
src=${NTPD_SRC:?NTPD_SRC}
d=$1
mkdir -p "$d"
"${HBNF:?HBNF}" /w/grammars/bind/ntpd.hbnf --backend=c --conf > "$d/conf.txt"
awk '/^===== conf.h =====$/{f="h"; next} /^===== conf.c =====$/{f="c"; next}
     f=="h"{print > "'"$d"'/conf.h"} f=="c"{print > "'"$d"'/conf.c"}' "$d/conf.txt"
gcc -O2 -std=gnu11 -D_GNU_SOURCE -w -include "$here/shim/compat.h" \
	-I"$d" -I"$src" -I"$here/shim" -I/w/tests/bsdinc -I"$here/../drv" \
	"$d/conf.c" "$here/stubs.c" "$here/main-ntpd.c" -o "$d/hbnfd"
