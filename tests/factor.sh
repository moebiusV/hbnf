#!/bin/sh
# Alternatives that begin with the same elements are read once.  tests/factor/ladder.hbnf is twelve levels of
# `e = x 1*( op x ) | x`: a parser that read x again for the bare alternative would take twice as long at each
# level, and parenthesised input such as ((((7)))) would not finish.  Each line of tests/factor/cases.txt is a
# verdict (ok or bad) and an input; every one must come out as written, within five seconds.
#   HBNF=/path/to/hbnf sh tests/factor.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/factor/ladder.hbnf --backend=c > "$W/p.c" 2> "$W/err" \
	|| { echo "factor: FAIL (does not generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/m.c"
${CC:-cc} -O1 -w -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$root" "$W/m.c" -o "$W/check" 2> "$W/cc.err" \
	|| { echo "factor: FAIL (does not compile: $(head -c 300 "$W/cc.err"))"; exit 1; }
fail=0; n=0
while IFS="$(printf '\t')" read -r want input; do
	n=$((n + 1))
	printf '%s' "$input" > "$W/in.txt"
	got=$(timeout 5 "$W/check" "$W/in.txt" 2> /dev/null | cut -d' ' -f1)
	[ -n "$got" ] || got=TIMEOUT
	[ "$got" = "$want" ] || { echo "factor: FAIL (\`$input\` should be $want and is $got)"; fail=1; }
done < tests/factor/cases.txt
# the shared beginning is read once, in the code too: the bare alternative has no second read of the operand
if [ $fail = 0 ]; then
	echo "factor: OK ($n inputs through a twelve-level ladder of x 1*( op x ) | x, none slow)"
fi
exit $fail
