#!/bin/sh
# `hidden`: a rule that is only text can be declared (`hidden sp = ...`) or listed
# (`hidden sp`); it is matched and keeps nothing in the tree.  A rule that builds structure,
# or the rule the grammar starts from, cannot be.
#   HBNF=/path/to/hbnf sh tests/hidden.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
for f in decl directive hyper; do
	"$CLI" tests/hidden/$f.hbnf --backend=c > "$W/$f.c" 2> "$W/$f.err" \
		|| { echo "hidden: FAIL ($f: $(head -c 200 "$W/$f.err"))"; fail=1; continue; }
	# the hidden token's value is the empty string: no copy of its text
	grep -q '\*out = ""; p->pos += n;' "$W/$f.c" \
		|| { echo "hidden: FAIL ($f: the hidden token still copies its text)"; fail=1; }
	grep -c '\*out = ""; p->pos += n;' "$W/$f.c" | grep -q '^1$' \
		|| { echo "hidden: FAIL ($f: more than one rule is hidden)"; fail=1; }
done
"$CLI" tests/hidden/phrase.hbnf --backend=c 2>&1 > /dev/null | grep -q 'builds structure' \
	|| { echo "hidden: FAIL (a hidden rule that builds structure was accepted)"; fail=1; }
"$CLI" tests/hidden/root.hbnf --backend=c 2>&1 > /dev/null | grep -q 'the rule the grammar starts from' \
	|| { echo "hidden: FAIL (a hidden root was accepted)"; fail=1; }
[ $fail = 0 ] && echo "hidden: OK (declaration, directive, hyperrule; structure and root refused)"
exit $fail
