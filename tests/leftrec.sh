#!/bin/sh
# Left recursion (tests/leftrec/leftrec.hbnf), which hbnf reads as a loop:
# a list with an empty base, parse.y's host_list, an operator rule folded to
# the left, and `string : string STRING | STRING`.  good.conf must parse as
# tests/leftrec/expected.txt says, each *.bad must fail, and a 100,000-term
# sum must parse with a 256 KB stack.  Then the left recursion hbnf refuses.
#   HBNF_CLI=/path/to/hbnf_cli sh tests/leftrec.sh     (default ./hbnf_cli)
set -u
cd "$(dirname "$0")/.."
CLI=${HBNF_CLI:-./hbnf_cli}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/leftrec/leftrec.hbnf --backend=c > "$W/l.c" || { echo "leftrec: FAIL (generate)"; exit 1; }
cat "$W/l.c" tests/leftrec/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/leftrec" \
    2> "$W/cc.txt" || { echo "leftrec: FAIL (compile)"; head -5 "$W/cc.txt"; exit 1; }
(cd tests/leftrec && "$W/leftrec" good.conf *.bad) > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/leftrec/expected.txt; then
	echo "leftrec: FAIL"; diff -u tests/leftrec/expected.txt "$W/got.txt" | head -20; exit 1
fi
echo "leftrec: OK (good.conf and the .bad configs)"

awk 'BEGIN { printf "calc 1"; for (i = 1; i < 100000; i++) printf " + 1"; printf ";\n" }' > "$W/big.conf"
got=$(ulimit -s 256; "$W/leftrec" "$W/big.conf" | tail -1)
if [ "$got" != "  calc (100000 terms) = 100000" ]; then
	echo "leftrec: FAIL (100,000 terms with a 256 KB stack: $got)"; exit 1
fi
echo "leftrec: OK (100,000 terms with a 256 KB stack)"

# Schemas hbnf must refuse, with the reason it gives.
refuse() {
	printf '%s\n' "$2" > "$W/bad.hbnf"
	if "$CLI" "$W/bad.hbnf" --backend=c > /dev/null 2> "$W/err.txt"; then
		echo "leftrec: FAIL (accepted: $2)"; exit 1
	fi
	grep -q "$1" "$W/err.txt" || { echo "leftrec: FAIL ($2: $(tail -1 "$W/err.txt"))"; exit 1; }
}
refuse "through another rule (a -> b -> a)" 'a = b "x" | "y"
b = a "z"'
refuse "after something that can match nothing (a -> a)" 'a = opt a "x" | "y"
opt = *( "p" )'
refuse "every alternative begins with .a., so it can never start" 'a = a "x" | a "y"'
refuse "the alternative .a. is the rule itself" 'a = a | "x"'
refuse "an empty alternative beside the other bases" 'a = a "x" | "y" |'
echo "leftrec: OK (refusals)"
