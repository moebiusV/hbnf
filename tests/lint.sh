#!/bin/sh
# --lint (and only with it) says where an ordered choice `|` could be written `/`: the alternatives are told
# apart in the order written, so the union means the same parse and leaves the order free.  tests/lint/pipes.hbnf
# has the choices that are suggested, and a union, a set of characters and choices with a core type, which are not.
#   HBNF=/path/to/hbnf sh tests/lint.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0
"$CLI" tests/lint/pipes.hbnf --backend=c --lint > /dev/null 2> "$W/lint.err" || { echo "lint: FAIL (does not generate: $(head -c 300 "$W/lint.err"))"; exit 1; }
"$CLI" tests/lint/pipes.hbnf --backend=c > /dev/null 2> "$W/plain.err" || { echo "lint: FAIL (does not generate without --lint)"; exit 1; }
for rule in setget xyz; do
	grep -A1 "is ordered choice" "$W/lint.err" | grep -q "^  $rule " \
		|| { echo "lint: FAIL (no suggestion in $rule)"; fail=1; }
done
n=$(grep -c "is ordered choice" "$W/lint.err")
[ "$n" = 2 ] || { echo "lint: FAIL ($n suggestions, wanted 2: $(grep -A1 'is ordered choice' "$W/lint.err" | grep '^  ' | cut -c1-40 | tr '\n' ' '))"; fail=1; }
grep -q "ordered choice" "$W/plain.err" && { echo "lint: FAIL (said without --lint)"; fail=1; }
# the suggestion is right: the grammar with `/` in its place gives the same parser
sed '/^setget /s/ | / \/ /g; /^xyz /s/ | / \/ /g' tests/lint/pipes.hbnf > tests/lint/_union.hbnf
"$CLI" tests/lint/pipes.hbnf --backend=c > "$W/a.c" 2> /dev/null
"$CLI" tests/lint/_union.hbnf --backend=c > "$W/b.c" 2> "$W/b.err"
rm -f tests/lint/_union.hbnf
cmp -s "$W/a.c" "$W/b.c" || { echo "lint: FAIL (the grammar with \`/\` where the lint says gives another parser)"; fail=1; }
[ $fail = 0 ] && echo "lint: OK (the two choices that could be unions are named, the others are not, and the union gives the same parser)"
exit $fail
