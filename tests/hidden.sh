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
# a hidden rule that builds structure (item 4): read into a scratch value, no field in the tree, the text still has to match
"$CLI" tests/hidden/structure.hbnf --backend=c > "$W/st.c" 2> "$W/st.err" \
	|| { echo "hidden: FAIL (structure: $(head -c 300 "$W/st.err"))"; fail=1; }
if [ -s "$W/st.c" ]; then
	sed -n '/^struct [a-z_]*doc_s {/,/^};/p' "$W/st.c" | grep -q 'mark' \
		&& { echo "hidden: FAIL (structure: the hidden rule is a field of the tree)"; fail=1; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/st.c")
	cat "$W/st.c" corpus/c/check.c > "$W/stm.c"
	cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/stm.c" -o "$W/st" 2> "$W/cc.txt" \
		|| { echo "hidden: FAIL (structure: cc: $(head -c 300 "$W/cc.txt"))"; fail=1; }
	for c in "ok abc:#12;xyz" "bad abc:#x;xyz" "bad abc:xyz"; do
		printf '%s' "${c#* }" > "$W/t.txt"
		[ -x "$W/st" ] && [ "$("$W/st" "$W/t.txt" | cut -d' ' -f1)" = "${c%% *}" ] \
			|| { echo "hidden: FAIL (structure: [${c#* }] should be ${c%% *})"; fail=1; }
	done
fi
for be in rust zig ada; do
	"$CLI" tests/hidden/structure.hbnf --backend=$be > /dev/null 2> "$W/st.err" \
		|| { echo "hidden: FAIL (structure, $be: $(head -c 300 "$W/st.err"))"; fail=1; }
done
"$CLI" tests/hidden/root.hbnf --backend=c 2>&1 > /dev/null | grep -q 'the rule the grammar starts from' \
	|| { echo "hidden: FAIL (a hidden root was accepted)"; fail=1; }
[ $fail = 0 ] && echo "hidden: OK (declaration, directive, hyperrule; a rule that builds structure hidden; the root refused)"
exit $fail
