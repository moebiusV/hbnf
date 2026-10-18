#!/bin/sh
# The AST and its walker (RFCPLAN.md 7d): every node records the alternative it
# took, and walk_<rule> calls back on entering and leaving each node with the
# path that led to it.  tests/ast/main.c walks tests/ast/ast.hbnf's tree; the
# output must be tests/ast/expected.txt.
#   HBNF=/path/to/hbnf sh tests/ast.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/ast/ast.hbnf --backend=c --ast-tools > "$W/a.c" || { echo "ast: FAIL (generate)"; exit 1; }
cat "$W/a.c" tests/ast/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/ast" \
    2> "$W/cc.txt" || { echo "ast: FAIL (compile)"; head -5 "$W/cc.txt"; exit 1; }
"$W/ast" > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/ast/expected.txt; then
	echo "ast: FAIL"; diff -u tests/ast/expected.txt "$W/got.txt" | head -20; exit 1
fi
echo "ast: OK (the walk, a skip, a stop)"
