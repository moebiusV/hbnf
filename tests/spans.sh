#!/bin/sh
# Spans and parents (RFCPLAN.md 7d): with --spans every node knows where it is in
# the text (_pos, _end; node_span, node_where), and with --parents which node
# holds it (node_link, node_parent).  tests/spans/main.c walks the tree of
# tests/ast/ast.hbnf; the output must be tests/spans/expected.txt.
#   HBNF=/path/to/hbnf sh tests/spans.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/ast/ast.hbnf --backend=c --ast --spans --parents > "$W/a.c" \
    || { echo "spans: FAIL (generate)"; exit 1; }
cat "$W/a.c" tests/spans/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/spans" \
    2> "$W/cc.txt" || { echo "spans: FAIL (compile)"; head -5 "$W/cc.txt"; exit 1; }
"$W/spans" > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/spans/expected.txt; then
	echo "spans: FAIL"; diff -u tests/spans/expected.txt "$W/got.txt" | head -30; exit 1
fi
echo "spans: OK (places and parents)"
