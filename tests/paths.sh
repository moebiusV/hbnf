#!/bin/sh
# Errors that say where the parser was (--paths): the rules it was reading when
# it got as far as it did, so `expected a value, found ;` also says it was in
# config > entry > block > entry.  tests/paths/main.c feeds bad input to the
# parser of tests/ast/ast.hbnf; the output must be tests/paths/expected.txt.
#   HBNF=/path/to/hbnf sh tests/paths.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/ast/ast.hbnf --backend=c --paths > "$W/p.c" || { echo "paths: FAIL (generate)"; exit 1; }
cat "$W/p.c" tests/paths/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/paths" \
    2> "$W/cc.txt" || { echo "paths: FAIL (compile)"; head -5 "$W/cc.txt"; exit 1; }
"$W/paths" > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/paths/expected.txt; then
	echo "paths: FAIL"; diff -u tests/paths/expected.txt "$W/got.txt" | head -30; exit 1
fi
echo "paths: OK (errors name the rules)"
