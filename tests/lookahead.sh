#!/bin/sh
# Lookahead: `!x` and `&x` test what is next without consuming it.  The
# parser of tests/lookahead/look.hbnf reads  a: b;  as a label and  a := b;
# as an assignment although both start with a colon; the output must be
# tests/lookahead/expected.txt.
#   HBNF=/path/to/hbnf sh tests/lookahead.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/lookahead/look.hbnf --backend=c --ast > "$W/c.c" 2> "$W/err" \
    || { echo "lookahead: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
cat "$W/c.c" tests/lookahead/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/look" \
    2> "$W/cc.txt" || { echo "lookahead: FAIL (compile)"; head -8 "$W/cc.txt"; exit 1; }
"$W/look" > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/lookahead/expected.txt; then
	echo "lookahead: FAIL"; diff -u tests/lookahead/expected.txt "$W/got.txt" | head -30; exit 1
fi
echo "lookahead: OK (a colon and a :=)"
