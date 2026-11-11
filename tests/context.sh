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
# the set does not trust the bytes of the name last asked about: a block that overwrites its buffer and adds
# (tests/context/ctxhash.hbnf) must find what it added
"$CLI" tests/context/ctxhash.hbnf --backend=c > "$W/h.c" 2> "$W/err" \
    || { echo "context: FAIL (ctxhash generate: $(head -c 300 "$W/err"))"; exit 1; }
cat "$W/h.c" corpus/c/check.c > "$W/hm.c"
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/h.c")
cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/hm.c" -o "$W/hash" 2> "$W/cc.txt" \
    || { echo "context: FAIL (ctxhash compile)"; head -8 "$W/cc.txt"; exit 1; }
printf 'xyz' > "$W/in.txt"
"$W/hash" "$W/in.txt" > "$W/hash.out" 2>&1 \
    || { echo "context: FAIL (a name added from a buffer that was overwritten is not found: $(head -c 200 "$W/hash.out"))"; exit 1; }
echo "context: OK (cast or product by what A is)"
