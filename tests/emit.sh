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
# a grammar whose choices are all told apart gets past the analysis and is generated
for f in read safe unrelated; do
	"$CLI" tests/emit/$f.hbnf --backend=c > "$W/$f.c" 2> "$W/$f.err" \
		|| { echo "emit: FAIL ($f: $(head -c 200 "$W/$f.err"))"; fail=1; }
done
for b in rust zig ada; do
	"$CLI" tests/emit/safe.hbnf --backend=$b 2>&1 > /dev/null | grep -q 'has an %emit, which only the C backend generates' \
		|| { echo "emit: FAIL (safe: $b does not refuse an %emit by name)"; fail=1; }
done
# the generated parser runs the emits in order, with `$$` and the elements as variables, and a
# parse that fails reports where without running them again
"$CLI" tests/emit/run.hbnf --backend=c > "$W/run.c" 2> "$W/run.err" \
	|| { echo "emit: FAIL (run: $(head -c 200 "$W/run.err"))"; fail=1; }
cat tests/emit/run.c >> "$W/run.c"
${CC:-cc} -std=gnu11 -w -o "$W/run" "$W/run.c" 2> "$W/cc.err" \
	|| { echo "emit: FAIL (run: does not compile: $(head -c 300 "$W/cc.err"))"; fail=1; }
if [ -x "$W/run" ]; then
	while read -r input want; do
		got=$("$W/run" "$input")
		[ "$got" = "$want" ] || { echo "emit: FAIL (run $input: got '$got', wanted '$want')"; fail=1; }
	done <<'CASES'
[] 0
[t] 1
[f] 0
[t,f,[t,t]] 3
[[[t]],[t,t],f] 3
[t,[] error 1:6
[t,x] error 1:4
CASES
fi
# each way an emit can be taken back is refused, naming the rule
refused() {   # refused FILE RULE TEXT
	"$CLI" tests/emit/$1.hbnf --backend=c 2>&1 > /dev/null | grep -q "rule \`$2\`: .*$3" \
		|| { echo "emit: FAIL ($1: not refused with \"$3\")"; fail=1; }
}
refused overlap-choice top 'can both begin with'
refused overlap-option top 'repeated or optional part'
# a repetition that can begin like what follows it is refused by the reader already, emit or none
"$CLI" tests/emit/overlap-repeat.hbnf --backend=c 2>&1 > /dev/null | grep -q 'matched greedily' \
	|| { echo "emit: FAIL (overlap-repeat: not refused)"; fail=1; }
# the reader allows nothing but literals and tokens in a lookahead, so an emit cannot get there
"$CLI" tests/emit/lookahead.hbnf --backend=c 2>&1 > /dev/null | grep -q 'looks at a literal' \
	|| { echo "emit: FAIL (lookahead: an %emit in a lookahead is not refused)"; fail=1; }
refused overlap-called top 'can both begin with'
[ $fail = 0 ] && echo "emit: OK (types read; %emit analysed and generated, each retry refused)"
exit $fail
