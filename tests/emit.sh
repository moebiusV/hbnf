#!/bin/sh
# The type after `::` and the `%emit` block (RFCPLAN.md step 15), as far as the reader goes:
# `name :: type = ...` is read for one word, several words and a parameterised rule; a head with no
# type, or no `=`, is refused with the form it wants; `%emit` is read between elements and at the
# end of a rule, and a grammar that uses it is refused by rule name until a backend generates it.
#   HBNF=/path/to/hbnf sh tests/emit.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
for f in plain typed; do
	"$CLI" tests/emit/$f.hbnf --backend=c > "$W/$f.c" 2> "$W/$f.err" \
		|| { echo "emit: FAIL ($f: $(head -c 200 "$W/$f.err"))"; fail=1; }
done
for f in no-type no-eq; do
	"$CLI" tests/emit/$f.hbnf --backend=c 2>&1 > /dev/null | grep -q 'expected `name :: type =`' \
		|| { echo "emit: FAIL ($f: not refused with the form it wants)"; fail=1; }
done
# a grammar whose choices are all told apart gets past the analysis, and is then refused only
# because no backend generates an %emit yet
for f in read safe unrelated; do
	"$CLI" tests/emit/$f.hbnf --backend=c 2>&1 > /dev/null | grep -q 'has an %emit, which the C backend does not generate yet' \
		|| { echo "emit: FAIL ($f: not accepted by the analysis, or not refused for lack of a backend)"; fail=1; }
done
# each way an emit can be taken back is refused, naming the rule
refused() {   # refused FILE RULE TEXT
	"$CLI" tests/emit/$1.hbnf --backend=c 2>&1 > /dev/null | grep -q "rule \`$2\`: .*$3" \
		|| { echo "emit: FAIL ($1: not refused with \"$3\")"; fail=1; }
}
refused overlap-choice top 'can both begin with'
refused overlap-option top_1 'repeated or optional part'
# a repetition that can begin like what follows it is refused by the reader already, emit or none
"$CLI" tests/emit/overlap-repeat.hbnf --backend=c 2>&1 > /dev/null | grep -q 'matched greedily' \
	|| { echo "emit: FAIL (overlap-repeat: not refused)"; fail=1; }
# the reader allows nothing but literals and tokens in a lookahead, so an emit cannot get there
"$CLI" tests/emit/lookahead.hbnf --backend=c 2>&1 > /dev/null | grep -q 'looks at a literal' \
	|| { echo "emit: FAIL (lookahead: an %emit in a lookahead is not refused)"; fail=1; }
refused overlap-called top 'can both begin with'
[ $fail = 0 ] && echo "emit: OK (types read; %emit analysed: safe choices accepted, each retry refused)"
exit $fail
