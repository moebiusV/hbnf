#!/bin/sh
# Context (RFCPLAN.md decision 13): `? types` asks a set of names, `%bind` adds
# to it, `%scope` ends what is added with a region, and a branch that gives up
# puts the set back.  tests/context/ctx.hbnf is C's `(A) * 0`: a cast when A is
# a typedef name, a product when it is not.  The output must be
# tests/context/expected.txt.
#   HBNF=/path/to/hbnf sh tests/context.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/context/ctx.hbnf --backend=c --ast > "$W/c.c" 2> "$W/err" \
    || { echo "context: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
cat "$W/c.c" tests/context/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/ctx" \
    2> "$W/cc.txt" || { echo "context: FAIL (compile)"; head -8 "$W/cc.txt"; exit 1; }
"$W/ctx" > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/context/expected.txt; then
	echo "context: FAIL"; diff -u tests/context/expected.txt "$W/got.txt" | head -30; exit 1
fi
echo "context: OK (cast or product by what A is)"
