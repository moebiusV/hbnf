#!/bin/sh
# parse_config one statement at a time, through a toy binding
# (tests/stmt/count.hbnf): macros, include, -D, every error reported with
# its file and line, and actions only on the statements they belong to.
# The generated conf.c must build warning-free with the daemons' flags.
#   HBNF_CLI=/path/to/hbnf_cli sh tests/stmt.sh     (default ./hbnf_cli)
set -u
cd "$(dirname "$0")/.."
CLI=${HBNF_CLI:-./hbnf_cli}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/stmt/count.hbnf --backend=c --conf > "$W/out.txt" || { echo "stmt: FAIL (generate)"; exit 1; }
awk -v d="$W" '/^===== conf\.h =====$/{f=1;next} /^===== conf\.c =====$/{f=2;next}
    f==1{print > d"/conf.h"} f==2{print > d"/conf.c"}' "$W/out.txt"
flags="-Wall -Wstrict-prototypes -Wmissing-prototypes -Wmissing-declarations
       -Wshadow -Wpointer-arith -Wcast-qual -Wsign-compare -Werror"
cc -std=gnu11 -D_GNU_SOURCE -Itests/bsdinc -I"$W" $flags "$W/conf.c" tests/stmt/main.c \
    -o "$W/count" 2> "$W/cc.txt" || { echo "stmt: FAIL (compile)"; head -5 "$W/cc.txt"; exit 1; }
(cd tests/stmt && "$W/count" top.conf ok.conf -Dpref=DoT -Dfw=198.51.100.1 top.conf ok.conf) \
    > "$W/got.txt" 2>&1
if cmp -s "$W/got.txt" tests/stmt/expected.txt; then
    echo "stmt: OK"
else
    echo "stmt: FAIL"; diff -u tests/stmt/expected.txt "$W/got.txt" | head -30; exit 1
fi
