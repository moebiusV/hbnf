#!/bin/sh
# A ladder of binary-operator levels (`a = b *( op b )`, `b = c *( op c )`, ...) is parsed with one look past its
# first operand: if no operator of the ladder can begin there, no level is entered.  The levels are found from
# the references, so tests/ladder/shuffled.hbnf writes them in no order and puts unrelated rules between them.
# This checks that the generator found the whole ladder (six levels, `or` down to `add`: the seventh rule, `mul`,
# holds its operand by pointer because the operand refers back to the ladder, so it is the operand the ladder
# ends at), that the parser built with the fast path (the default)
# and the plain one (--no-ladder) give the same verdict on every line of tests/ladder/cases.txt, that each gives
# the verdict written there, and that the types they declare are the same.
#   HBNF=/path/to/hbnf sh tests/ladder.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0
for mode in fast plain; do
	flag=; [ $mode = plain ] && flag=--no-ladder
	"$CLI" tests/ladder/shuffled.hbnf --backend=c --root=program $flag > "$W/$mode.c" 2> "$W/$mode.err" \
		|| { echo "ladder: FAIL ($mode does not generate: $(head -c 300 "$W/$mode.err"))"; exit 1; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$mode.c")
	cat "$W/$mode.c" corpus/c/check.c > "$W/$mode-m.c"
	${CC:-cc} -O1 -w -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$root" "$W/$mode-m.c" -o "$W/$mode-check" 2> "$W/cc.err" \
		|| { echo "ladder: FAIL ($mode does not compile: $(head -c 300 "$W/cc.err"))"; exit 1; }
	awk '/^static bool parse_/ {exit} {print}' "$W/$mode.c" > "$W/$mode-types.c"
done
# the generator found the ladder: six levels from the loosest, one fewer at each level down
found=$(grep -c '/\* a ladder of ' "$W/fast.c")
top=$(grep -c '/\* a ladder of 6 levels' "$W/fast.c")
[ "$found" = 6 ] && [ "$top" = 1 ] \
	|| { echo "ladder: FAIL (the generator found $found levels, $top of them the whole ladder of 6; each of the 6 rules should be a level of its own chain)"; fail=1; }
[ "$(grep -c '/\* a ladder of ' "$W/plain.c")" = 0 ] || { echo "ladder: FAIL (--no-ladder still writes the fast path)"; fail=1; }
cmp -s "$W/fast-types.c" "$W/plain-types.c" || { echo "ladder: FAIL (the declared types differ between the two parsers)"; fail=1; }
n=0
while IFS="$(printf '\t')" read -r want input; do
	n=$((n + 1))
	printf '%s' "$input" > "$W/in.txt"
	a=$("$W/fast-check" "$W/in.txt" 2> /dev/null | cut -d' ' -f1)
	b=$("$W/plain-check" "$W/in.txt" 2> /dev/null | cut -d' ' -f1)
	[ "$a" = "$b" ] || { echo "ladder: FAIL (\`$input\`: the fast path says $a, the plain parse $b)"; fail=1; }
	[ "$a" = "$want" ] || { echo "ladder: FAIL (\`$input\` should be $want and is $a)"; fail=1; }
done < tests/ladder/cases.txt
[ $fail = 0 ] && echo "ladder: OK (six levels found in a shuffled file; $n inputs agree with the plain parse and with their verdicts)"
exit $fail
