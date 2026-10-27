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
	# the hidden token's value is empty (the empty string, or a view of nothing): no copy of its text
	grep -Eq '\*out = (""|\(hbnf_str\)0); p->pos \+= n;' "$W/$f.c" \
		|| { echo "hidden: FAIL ($f: the hidden token still copies its text)"; fail=1; }
	grep -Ec '\*out = (""|\(hbnf_str\)0); p->pos \+= n;' "$W/$f.c" | grep -q '^1$' \
		|| { echo "hidden: FAIL ($f: more than one rule is hidden)"; fail=1; }
	# and the tree has no field for it
	! grep -Eq '^ +[a-z_0-9]*(dash|pad_a)_t [a-z_0-9]*(dash|pad_a);' "$W/$f.c" \
		|| { echo "hidden: FAIL ($f: the hidden rule is still a field of the tree)"; fail=1; }
done
# a hidden rule that repeats or is optional is hidden too: the tree has no field for it
"$CLI" tests/hidden/repeat.hbnf --backend=c > "$W/repeat.c" 2> "$W/repeat.err" \
	|| { echo "hidden: FAIL (repeat: $(head -c 200 "$W/repeat.err"))"; fail=1; }
sed -n '/^struct bnf_doc_s {/,/^};/p' "$W/repeat.c" | grep -c 'bnf_doc_[12]' | grep -q '^0$' \
	|| { echo "hidden: FAIL (repeat: a repeated hidden rule is still a field)"; fail=1; }
# the other backends keep no field for it either
for be in rust zig ada; do
	"$CLI" tests/hidden/decl.hbnf --backend=$be > "$W/decl.$be" 2> "$W/decl.$be.err" \
		|| { echo "hidden: FAIL (decl, $be: $(head -c 200 "$W/decl.$be.err"))"; fail=1; continue; }
	grep -Eiq '^ +(pub )?bnf_dash *: *bnf_?dash' "$W/decl.$be" \
		&& { echo "hidden: FAIL (decl, $be: the hidden rule is still a field of the tree)"; fail=1; }
done
"$CLI" tests/hidden/phrase.hbnf --backend=c 2>&1 > /dev/null | grep -q 'builds structure' \
	|| { echo "hidden: FAIL (a hidden rule that builds structure was accepted)"; fail=1; }
"$CLI" tests/hidden/root.hbnf --backend=c 2>&1 > /dev/null | grep -q 'the rule the grammar starts from' \
	|| { echo "hidden: FAIL (a hidden root was accepted)"; fail=1; }
[ $fail = 0 ] && echo "hidden: OK (declaration, directive, hyperrule; structure and root refused)"
exit $fail
