#!/bin/sh
# The set-logic spellings (CONTEXTS.md section 29, chosen in R643): they are sugar, so each generates exactly what the spelling it stands for
# generates, in every backend.
#   - `x in S`, `x ∈ S` are `x ? S`; `x not in S`, `x ∉ S` are `x ?! S` (tests/setlogic/member*.hbnf);
#   - `in ( "a" "ab" )` at the start of an alternative is one of the literals, the longest first: `"ab" | "a"`, an enum, and it
#     does not hide a member that is the front of another;
#   - `one of ( ... )` is `in ( ... )`; `a intersect b` (and `a ∩ b`) reads b over exactly the text a matched, in C so far;
#   - `all of ( a [b] c )`: each member once, in any order, one field for each member; `some of ( a b c )` one or more of them, `any of ( a b c )`
#     none or more; in C so far (the other backends refuse them by rule name);
#   - `x in ( ... )` after an element is not built yet and says so.
#   HBNF=/path/to/hbnf sh tests/setlogic.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0; n=0
same() {   # WHAT NEW OLD [BACKENDS]: the same generated text in each backend
	for b in ${4:-c rust zig ada}; do
		"$CLI" "$2" --backend=$b --package=Sl > "$W/n" 2> "$W/ne"; "$CLI" "$3" --backend=$b --package=Sl > "$W/o" 2> "$W/oe"
		n=$((n + 1))
		cmp -s "$W/n" "$W/o" && [ -s "$W/n" ] || { echo "setlogic: FAIL ($1, $b: not the text of $3: $(head -c 200 "$W/ne"))"; fail=1; }
	done
}
same "in and not in" tests/setlogic/member.hbnf tests/setlogic/member-old.hbnf c     # (a grammar with `context` is C only)
same "∈ and ∉" tests/setlogic/member-unicode.hbnf tests/setlogic/member-old.hbnf c
printf 'prefix none\nwhitespace none\nkw = in ( "a" "abc" "ab" )\n' > "$W/one.hbnf"
printf 'prefix none\nwhitespace none\nkw = "abc" | "ab" | "a"\n' > "$W/one-old.hbnf"
same "one of, the longest first" "$W/one.hbnf" "$W/one-old.hbnf"
printf 'prefix none\nwhitespace none\nkw = ∈ ( "a" "abc" "ab" )\n' > "$W/one-u.hbnf"
same "one of with ∈" "$W/one-u.hbnf" "$W/one-old.hbnf"
printf 'prefix none\nwhitespace none\nkw = one of ( "a" "abc" "ab" )\n' > "$W/one-w.hbnf"
same "one of" "$W/one-w.hbnf" "$W/one-old.hbnf"
printf 'prefix none\nwhitespace none\nkw = one of ( x y z )\nx = "1"\ny = "2"\nz = "3"\n' > "$W/rules.hbnf"
printf 'prefix none\nwhitespace none\nkw = x | y | z\nx = "1"\ny = "2"\nz = "3"\n' > "$W/rules-old.hbnf"
same "one of rules, as the choice reads them" "$W/rules.hbnf" "$W/rules-old.hbnf"
# it reads: the longest member is not hidden by a front of it
"$CLI" "$W/one.hbnf" --backend=c > "$W/one.c" 2> /dev/null
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/one.c")
cat "$W/one.c" corpus/c/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/m.c" -o "$W/check" 2> "$W/cc.txt" || { echo "setlogic: FAIL (the set does not compile: $(head -c 300 "$W/cc.txt"))"; exit 1; }
for c in "ok a" "ok ab" "ok abc" "bad abcd" "bad x"; do
	printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/check" "$W/t.txt" | cut -d' ' -f1)
	n=$((n + 1)); [ "$got" = "${c%% *}" ] || { echo "setlogic: FAIL (in ( \"a\" \"abc\" \"ab\" ) on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
done
# `a intersect b`: b matches exactly the text a matched; C only so far
cat > "$W/both.hbnf" <<'EOG'
prefix none
whitespace none
include "../../grammars/common.hbnf"
doc   = item *( "," item )
item  = word intersect short
word  = 1*ALPHA
short = 1*3ALPHA
EOG
cp "$W/both.hbnf" tests/setlogic/_both.hbnf
sed 's/ intersect / ∩ /' "$W/both.hbnf" > tests/setlogic/_both-u.hbnf
"$CLI" tests/setlogic/_both.hbnf --backend=c > "$W/b.c" 2> "$W/err" || { echo "setlogic: FAIL (intersect does not generate: $(head -c 300 "$W/err"))"; fail=1; }
"$CLI" tests/setlogic/_both-u.hbnf --backend=c > "$W/bu.c" 2> /dev/null
n=$((n + 1)); cmp -s "$W/b.c" "$W/bu.c" || { echo "setlogic: FAIL (∩ is not what intersect generates)"; fail=1; }
if [ -s "$W/b.c" ]; then
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/b.c")
	cat "$W/b.c" corpus/c/check.c > "$W/mb.c"
	cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/mb.c" -o "$W/checkb" 2> "$W/cc.txt" || { echo "setlogic: FAIL (intersect: cc: $(head -c 300 "$W/cc.txt"))"; fail=1; }
	for c in "ok ab" "ok abc,x" "bad abcd" "bad ab,abcde" "bad 1"; do
		printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/checkb" "$W/t.txt" | cut -d' ' -f1)
		n=$((n + 1)); [ "$got" = "${c%% *}" ] || { echo "setlogic: FAIL (word intersect short on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
	done
fi
rm -f tests/setlogic/_both.hbnf tests/setlogic/_both-u.hbnf
for b in rust zig ada; do
	printf 'prefix none\nwhitespace none\ninclude "../../grammars/common.hbnf"\ntop = word intersect short\nword = 1*ALPHA\nshort = 1*3ALPHA\n' > tests/setlogic/_b.hbnf
	"$CLI" tests/setlogic/_b.hbnf --backend=$b --package=Sl 2>&1 > /dev/null | grep -q 'has `intersect` (an intersection), which only the C backend generates' \
		|| { echo "setlogic: FAIL ($b does not say that intersect is C only)"; fail=1; }
	n=$((n + 1))
done
rm -f tests/setlogic/_b.hbnf
# `in` has the one meaning (R645 and CONTEXTS section 29): a grammar with a rule of that name renames it (the POSIX shell's is `in_word`)
printf 'prefix none\nwhitespace none\ntop = name in sep\nname = 1*0x61..0x7a\nin = "in"\nsep = ";"\n' > "$W/inrule.hbnf"
"$CLI" "$W/inrule.hbnf" --backend=c 2>&1 > /dev/null | grep -q 'is not a context' \
	|| { echo "setlogic: FAIL (a name after in is read as a set: a rule named in is not refused with what it is read as)"; fail=1; }
n=$((n + 1))
# `all of ( a [b] c )` (R649): each member once, in any order, a member in `[ ]` may be left out; one field for each member
chk() {	# a grammar, then cases "ok TEXT" or "bad TEXT"
	g=$1; shift
	"$CLI" "$g" --backend=c > "$W/a.c" 2> "$W/err" || { echo "setlogic: FAIL ($g does not generate: $(head -c 300 "$W/err"))"; fail=1; return; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/a.c")
	cat "$W/a.c" corpus/c/check.c > "$W/ma.c"
	cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/ma.c" -o "$W/checka" 2> "$W/cc.txt" || { echo "setlogic: FAIL ($g: cc: $(head -c 300 "$W/cc.txt"))"; fail=1; return; }
	for c in "$@"; do
		printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/checka" "$W/t.txt" | cut -d' ' -f1)
		n=$((n + 1)); [ "$got" = "${c%% *}" ] || { echo "setlogic: FAIL ($g on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
	done
}
chk tests/setlogic/allof.hbnf "ok Dp1." "ok Dp1usage." "ok Dusagep1." "ok Dv2p1." "ok Dv2usagep1." "ok Dp1usagev2." "ok Dv2p1usage." "ok Dusagev2p1." \
	"bad D." "bad Dusage." "bad Dp1p2." "bad Dp1usageusage." "bad Dp1v2v3." "bad Dp1"
chk tests/setlogic/someof.hbnf "ok Dp1." "ok Dusage." "ok Dv2usagep1." "ok Dusagep1v2." "bad D." "bad Dp1p2." "bad Dusageusage." "bad Dx."
chk tests/setlogic/anyof.hbnf "ok D." "ok Dp1." "ok Dusagep1." "ok Dp1usage." "bad Dp1p2." "bad Dx."
chk tests/setlogic/allof-first.hbnf "ok p1." "ok usagep1." "ok z." "ok p1.z.usagep2." "bad usage." "bad x." "bad p1usage"
chk tests/setlogic/allof-opt.hbnf "ok D." "ok Dp1." "ok Dusage." "ok Dusagep1." "ok Dp1usage." "bad Dp1p2." "bad Dx."
chk tests/setlogic/allof-two.hbnf "ok ab-c" "ok ba-cd" "ok ba-dc" "bad a-c" "bad ab-d" "bad ab-cc" "bad aab-c"
chk tests/setlogic/allof-rec.hbnf "ok D3x4." "ok Dtag3x4." "ok D3x4tag." "bad D3y4." "bad Dtag." "bad D3x4tagtag." "bad D3x"
"$CLI" tests/setlogic/allof.hbnf --backend=c > "$W/f.c" 2> /dev/null
n=$((n + 1)); [ "$(sed -n '/^struct decl_s {$/,/^};$/p' "$W/f.c" | tr -d ' \n')" = "structdecl_s{pic_tpic;usage_tusage;value_tvalue;};" ] \
	|| { echo "setlogic: FAIL (all of: the record has not a field for each member)"; fail=1; }
for b in rust zig ada; do
	"$CLI" tests/setlogic/allof.hbnf --backend=$b --package=Sl 2>&1 > /dev/null | grep -q 'has `all of ( ... )`.*only the C backend generates' \
		|| { echo "setlogic: FAIL ($b does not say that all of is C only)"; fail=1; }
	n=$((n + 1))
done
printf 'prefix none\nwhitespace none\ntop = all of ( a a )\na = "a"\n' > "$W/dup.hbnf"
"$CLI" "$W/dup.hbnf" --backend=c 2>&1 > /dev/null | grep -q 'names `a` twice' || { echo "setlogic: FAIL (all of ( a a ) is not refused)"; fail=1; }
n=$((n + 1))
# a written set after an element is not built yet
printf 'prefix none\nwhitespace none\ntop = name in ( "a" "b" )\nname = 1*0x61..0x7a\n' > "$W/infix.hbnf"
"$CLI" "$W/infix.hbnf" --backend=c 2>&1 > /dev/null | grep -q 'is not built yet' \
	|| { echo "setlogic: FAIL (x in ( ... ) after an element is not refused with what is not built)"; fail=1; }
n=$((n + 1))
[ $fail = 0 ] && echo "setlogic: OK ($n results: in, not in, ∈, ∉ and the written set generate what ?, ?! and the longest-first choice do, in four backends where the grammar can go to them)"
exit $fail
