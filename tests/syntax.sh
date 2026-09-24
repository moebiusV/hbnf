#!/bin/sh
# hbnf's notation beyond RFC 5234 (tests/syntax/syntax.hbnf): `|` and `/`,
# %i and %s literals, a %i keyword, C escapes in a literal, %scan{ } and
# %action{ }.  good.conf must parse as tests/syntax/expected.txt says; each
# *.bad must fail.
#   HBNF_CLI=/path/to/hbnf_cli sh tests/syntax.sh      (default ./hbnf_cli)
set -u
cd "$(dirname "$0")/.."
CLI=${HBNF_CLI:-./hbnf_cli}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/syntax/syntax.hbnf --backend=c > "$W/s.c" || { echo "syntax: FAIL (generate)"; exit 1; }
cat "$W/s.c" tests/syntax/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/syntax" \
    2> "$W/cc.txt" || { echo "syntax: FAIL (compile)"; head -5 "$W/cc.txt"; exit 1; }
(cd tests/syntax && "$W/syntax" good.conf *.bad) > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/syntax/expected.txt; then
	echo "syntax: FAIL"; diff -u tests/syntax/expected.txt "$W/got.txt" | head -20; exit 1
fi
echo "syntax: OK (good.conf and the .bad configs)"

# Schemas hbnf must refuse, with the reason it gives.
refuse() {
	printf '%s\n' "$2" > "$W/bad.hbnf"
	if "$CLI" "$W/bad.hbnf" --backend=c > /dev/null 2> "$W/err.txt"; then
		echo "syntax: FAIL (accepted: $2)"; exit 1
	fi
	grep -q "$1" "$W/err.txt" || { echo "syntax: FAIL ($2: $(tail -1 "$W/err.txt"))"; exit 1; }
}
refuse "numeric terminals are not supported" 'r = %x41-5A'
refuse "takes the place of a pattern" 'r = "a" %scan{ return 0; }'
refuse "both with %i and without" 'r = "go" | x
x = %i"go" "now"'
refuse "an action runs on a node" 'r = *( e )
e = "a" m
m = "x" | "y" %action{ (void)n; }'
refuse "bad octal escape" 'r = "\777"'
echo "syntax: OK (refusals)"
