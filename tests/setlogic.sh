#!/bin/sh
# The set-logic spellings (CONTEXTS.md section 29, chosen in R643): they are sugar, so each generates exactly what the spelling it stands for
# generates, in every backend.
#   - `x in S`, `x ∈ S` are `x ? S`; `x not in S`, `x ∉ S` are `x ?! S` (tests/setlogic/member*.hbnf);
#   - `in ( "a" "ab" )` at the start of an alternative is one of the literals, the longest first: `"ab" | "a"`, an enum, and it
#     does not hide a member that is the front of another;
#   - `one of ( ... )` is `in ( ... )`; `a intersect b` (and `a ∩ b`) reads b over exactly the text a matched, in C so far;
#   - `all of ( a [b] c )`: each member once, in any order, one field for each member; `some of ( a b c )` one or more of them, `any of ( a b c )`
#     none or more; `( a b c ) choose 2` takes 2 of them in the order written (3 shapes), `permute 2` in any order (6 shapes), the count n or n*m;
#     in C so far (the other backends refuse them by rule name);
#   - `x in ( "a" "b" )` after an element: the text x matched is one of them (C so far); `x in X not in Z` chains the tests.
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
same "in and not in are ∈ and ∉" tests/setlogic/member.hbnf tests/setlogic/member-unicode.hbnf c     # (a grammar with `context` is C only)
# the old spellings `x ? S` and `x ?! S` are refused, with the new spelling in the message (R647)
"$CLI" tests/setlogic/member-old.hbnf --backend=c 2>&1 > /dev/null | grep -q '`x ? S` is written `x in S`' \
	|| { echo "setlogic: FAIL (x ? S is not refused with in)"; fail=1; }
n=$((n + 1))
printf 'prefix none\ncontext types\nwhitespace none\ntop = name ?! types\nname = 1*0x61..0x7a\n' > "$W/neg.hbnf"
"$CLI" "$W/neg.hbnf" --backend=c 2>&1 > /dev/null | grep -q '`x ?! S` is written `x not in S`' \
	|| { echo "setlogic: FAIL (x ?! S is not refused with not in)"; fail=1; }
n=$((n + 1))
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
# chk GRAMMAR CASES...: each case "ok TEXT" or "bad TEXT" is read in C and, where rustc is installed, in Rust
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
	# the same cases in the Rust backend, where rustc is installed and the grammar can go to it (the others refuse by rule name)
	if command -v rustc > /dev/null 2>&1; then
		mkdir -p "$W/rs"; rm -f "$W/rs/m"
		if "$CLI" "$g" --backend=rust > "$W/rs/l.rs" 2> "$W/err"; then
			sed "s/MODULE/l/g" corpus/c/check.rs > "$W/rs/m.rs"
			(cd "$W/rs" && rustc --edition 2021 -A warnings -C opt-level=0 -o m m.rs > cc.txt 2>&1) \
				|| { echo "setlogic: FAIL ($g: the Rust parser does not compile: $(grep -m2 error "$W/rs/cc.txt" | head -c 300))"; fail=1; return; }
			for c in "$@"; do
				printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/rs/m" "$W/t.txt" 2>&1 | cut -d' ' -f1 | head -1)
				n=$((n + 1)); [ "$got" = "${c%% *}" ] || { echo "setlogic: FAIL ($g in Rust on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
			done
		elif ! grep -q 'only the C backend\|in C so far' "$W/err"; then
			echo "setlogic: FAIL ($g does not generate in Rust: $(head -c 300 "$W/err"))"; fail=1
		fi
	fi
	# and in Zig, where zig is installed: the cases are embedded in one check program, which says ok or bad for each
	if command -v zig > /dev/null 2>&1; then
		d=$W/zg; rm -rf "$d"; mkdir -p "$d"
		if "$CLI" "$g" --backend=zig > "$d/l.zig" 2> "$W/err"; then
			k=0; : > "$d/files.txt"; : > "$d/want.txt"
			for c in "$@"; do
				printf '%s' "${c#* }" > "$d/f$k.dat"; printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
				echo "${c%% *}" >> "$d/want.txt"; k=$((k + 1))
			done
			sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
			if (cd "$d" && zig build-exe m.zig -O Debug -femit-bin=m > cc.txt 2>&1); then
				"$d/m" > "$d/out" 2>&1
				k=0
				for c in "$@"; do
					got=$(grep -aF "c$k.txt" "$d/out" | head -1 | cut -d' ' -f1)
					n=$((n + 1)); [ "$got" = "${c%% *}" ] || { echo "setlogic: FAIL ($g in Zig on [${c#* }] should be ${c%% *} and is ${got:-none})"; fail=1; }
					k=$((k + 1))
				done
			else echo "setlogic: FAIL ($g: the Zig parser does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
		elif ! grep -q 'only the C backend\|in C so far' "$W/err"; then
			echo "setlogic: FAIL ($g does not generate in Zig: $(head -c 300 "$W/err"))"; fail=1
		fi
	fi
	# and in Ada, where gnatmake is installed: one file for each case, one check program for all of them
	if command -v gnatmake > /dev/null 2>&1; then
		d=$W/ad; rm -rf "$d"; mkdir -p "$d/cases"
		if "$CLI" "$g" --backend=ada --package=Sl > "$d/all.ada" 2> "$W/err"; then
			root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
			sed "s/MODULE/Sl/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
			k=0; for c in "$@"; do printf '%s' "${c#* }" > "$d/cases/c$k.txt"; k=$((k + 1)); done
			if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
				k=0
				for c in "$@"; do
					got=$("$d/m" "$d/cases/c$k.txt" 2>&1 | cut -d' ' -f1 | head -1)
					n=$((n + 1)); [ "$got" = "${c%% *}" ] || { echo "setlogic: FAIL ($g in Ada on [${c#* }] should be ${c%% *} and is ${got:-none})"; fail=1; }
					k=$((k + 1))
				done
			else echo "setlogic: FAIL ($g: the Ada parser does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
		elif ! grep -q 'only the C backend\|in C so far' "$W/err"; then
			echo "setlogic: FAIL ($g does not generate in Ada: $(head -c 300 "$W/err"))"; fail=1
		fi
	fi
}
# `a intersect b`: b matches exactly the text a matched, in C, Rust, Zig and Ada
cat > tests/setlogic/intersect.hbnf <<'EOG'
prefix none
whitespace none
include "../../grammars/common.hbnf"
doc   = item *( "," item )
item  = word intersect short
word  = 1*ALPHA
short = 1*3ALPHA
EOG
sed 's/ intersect / ∩ /' tests/setlogic/intersect.hbnf > tests/setlogic/intersect-u.hbnf
"$CLI" tests/setlogic/intersect.hbnf --backend=c > "$W/b.c" 2> /dev/null; "$CLI" tests/setlogic/intersect-u.hbnf --backend=c > "$W/bu.c" 2> /dev/null
n=$((n + 1)); cmp -s "$W/b.c" "$W/bu.c" || { echo "setlogic: FAIL (∩ is not what intersect generates)"; fail=1; }
chk tests/setlogic/intersect.hbnf "ok ab" "ok abc,x" "bad abcd" "bad ab,abcde" "bad 1"
# `in` has the one meaning (R645 and CONTEXTS section 29): a grammar with a rule of that name renames it (the POSIX shell's is `in_word`)
printf 'prefix none\nwhitespace none\ntop = name in sep\nname = 1*0x61..0x7a\nin = "in"\nsep = ";"\n' > "$W/inrule.hbnf"
"$CLI" "$W/inrule.hbnf" --backend=c 2>&1 > /dev/null | grep -q 'is not a context' \
	|| { echo "setlogic: FAIL (a name after in is read as a set: a rule named in is not refused with what it is read as)"; fail=1; }
n=$((n + 1))
# `all of ( a [b] c )` (R649): each member once, in any order, a member in `[ ]` may be left out; one field for each member
chk tests/setlogic/allof.hbnf "ok Dp1." "ok Dp1usage." "ok Dusagep1." "ok Dv2p1." "ok Dv2usagep1." "ok Dp1usagev2." "ok Dv2p1usage." "ok Dusagev2p1." \
	"bad D." "bad Dusage." "bad Dp1p2." "bad Dp1usageusage." "bad Dp1v2v3." "bad Dp1"
chk tests/setlogic/someof.hbnf "ok Dp1." "ok Dusage." "ok Dv2usagep1." "ok Dusagep1v2." "bad D." "bad Dp1p2." "bad Dusageusage." "bad Dx."
chk tests/setlogic/anyof.hbnf "ok D." "ok Dp1." "ok Dusagep1." "ok Dp1usage." "bad Dp1p2." "bad Dx."
chk tests/setlogic/permute.hbnf "ok Dab." "ok Dba." "ok Dac." "ok Dca." "ok Dbc." "ok Dcb." "bad Da." "bad Dabc." "bad Daa." "bad D."
chk tests/setlogic/choose.hbnf "ok Dab." "ok Dac." "ok Dbc." "bad Dba." "bad Dca." "bad Dcb." "bad Da." "bad Dabc." "bad Daa."
chk tests/setlogic/choose-range.hbnf "ok D." "ok Da." "ok Dc." "ok Dab." "ok Dac." "ok Dbc." "bad Dba." "bad Dabc." "bad Daa."
# `with replacement` (R4): permute 2 of 3 with replacement is 2*( a | b | c ), 9 shapes; choose 2 of 3 with replacement is the members in
# order, each repeated, 6 shapes, and counts them, so its members must be structures; the short forms are the same text
chk tests/setlogic/permute-repl.hbnf "ok Daa." "ok Dab." "ok Dba." "ok Dcc." "ok Dbc." "bad Da." "bad Dabc." "bad D."
chk tests/setlogic/short-pr.hbnf "ok Daa." "ok Dcb." "bad Da." "bad Dabc."
chk tests/setlogic/short-p.hbnf "ok Dab." "ok Dba." "bad Daa." "bad Da."
chk tests/setlogic/short-c.hbnf "ok Da." "ok Dab." "bad D." "bad Dabc." "bad Dba."
chk tests/setlogic/choose-repl.hbnf "ok Da1a1." "ok Da1b1." "ok Da1c12." "ok Db1b1." "ok Db1c1." "ok Dc1c1." "bad Db1a1." "bad Dc1a1." "bad Da1." "bad Da1b1c1." "bad D."
"$CLI" tests/setlogic/permute-repl.hbnf --backend=c > "$W/s1.c" 2> /dev/null; "$CLI" tests/setlogic/short-pr.hbnf --backend=c > "$W/s2.c" 2> /dev/null
# choose with replacement counts lists: C only
for b in rust zig ada; do
	"$CLI" tests/setlogic/choose-repl.hbnf --backend=$b 2>&1 > /dev/null | grep -q '`choose ... with replacement`, which only the C backend generates' \
		|| { echo "setlogic: FAIL ($b does not say that choose with replacement is C only)"; fail=1; }
	n=$((n + 1))
done
n=$((n + 1)); cmp -s "$W/s1.c" "$W/s2.c" || { echo "setlogic: FAIL (Pr(( ... ), 2) is not permute 2 with replacement)"; fail=1; }
printf 'prefix none\nwhitespace none\ntop = "D" ( a b ) choose 2 with replacement\na = "a"\nb = "b"\n' > "$W/wr.hbnf"
"$CLI" "$W/wr.hbnf" --backend=c 2>&1 > /dev/null | grep -q 'a member that is only text cannot be counted' || { echo "setlogic: FAIL (choose with replacement of text members is not refused)"; fail=1; }
n=$((n + 1))
# members that are literals, groups and repeated elements (R3); a member that matched nothing is not taken
chk tests/setlogic/allof-kinds.hbnf "ok Dp1#fk=2." "ok Dk=2#fp1." "ok D#fp1k=2." "ok Dxp1#fk=2." "ok Dp1x#fk=2." "bad Dp1#fk=2" "bad Dp1k=2." "bad D#fk=2." "bad Dp1#fk=2#f." "bad Dp1#fk=2xx."
chk tests/setlogic/anyof-rep.hbnf "ok D." "ok Daaa." "ok Dbbbb." "ok Dcc." "ok Dcccaabb." "ok Dbbcccaa." "bad Dc." "bad Dcccc." "bad Dabab."
chk tests/setlogic/allof-rep.hbnf "ok Da." "ok Daa." "ok Dabb." "ok Dbba." "bad D." "bad Dbb." "bad Dbab."
# `one of` keeps the order written, and moves a literal ahead only of an earlier one that is its front (R670, S5): a list with no
# such pair is the plain alternation, byte for byte (so the C grammars can use it)
printf 'prefix none\nwhitespace none\nkw = one of ( "extern" "static" "auto" "register" )\n' > "$W/o1.hbnf"
printf 'prefix none\nwhitespace none\nkw = "extern" | "static" | "auto" | "register"\n' > "$W/o1-old.hbnf"
same "one of keeps the order written" "$W/o1.hbnf" "$W/o1-old.hbnf"
printf 'prefix none\nwhitespace none\nkw = one of ( "x" "a" "ab" "y" "abc" )\n' > "$W/o2.hbnf"
printf 'prefix none\nwhitespace none\nkw = "x" | "abc" | "ab" | "a" | "y"\n' > "$W/o2-old.hbnf"
same "one of moves a literal ahead of its front only" "$W/o2.hbnf" "$W/o2-old.hbnf"
chk tests/setlogic/allof-first.hbnf "ok p1." "ok usagep1." "ok z." "ok p1.z.usagep2." "bad usage." "bad x." "bad p1usage"
chk tests/setlogic/allof-opt.hbnf "ok D." "ok Dp1." "ok Dusage." "ok Dusagep1." "ok Dp1usage." "bad Dp1p2." "bad Dx."
chk tests/setlogic/allof-two.hbnf "ok ab-c" "ok ba-cd" "ok ba-dc" "bad a-c" "bad ab-d" "bad ab-cc" "bad aab-c"
chk tests/setlogic/allof-rec.hbnf "ok D3x4." "ok Dtag3x4." "ok D3x4tag." "bad D3y4." "bad Dtag." "bad D3x4tagtag." "bad D3x"
"$CLI" tests/setlogic/allof.hbnf --backend=c > "$W/f.c" 2> /dev/null
n=$((n + 1)); [ "$(sed -n '/^struct decl_s {$/,/^};$/p' "$W/f.c" | tr -d ' \n')" = "structdecl_s{pic_tpic;usage_tusage;value_tvalue;};" ] \
	|| { echo "setlogic: FAIL (all of: the record has not a field for each member)"; fail=1; }
printf 'prefix none\nwhitespace none\ntop = all of ( a a )\na = "a"\n' > "$W/dup.hbnf"
"$CLI" "$W/dup.hbnf" --backend=c 2>&1 > /dev/null | grep -q 'names `a` twice' || { echo "setlogic: FAIL (all of ( a a ) is not refused)"; fail=1; }
n=$((n + 1))
# `x in ( "a" "b" )` after an element (R2): the text x matched is one of the literals written, or is read whole by a rule written;
# `x in X not in Z` (R1): the tests chain, each on the text x matched
chk tests/setlogic/inset.hbnf "ok int;" "ok char;long;int;" "ok " "bad integer;" "bad in;" "bad intx;" "bad ;"
chk tests/setlogic/inset-rule.hbnf "ok int;" "bad ab;"
chk tests/setlogic/inset-uni.hbnf "ok int;long;" "bad integer;"
"$CLI" tests/setlogic/inset.hbnf --backend=c > "$W/i1.c" 2> /dev/null; "$CLI" tests/setlogic/inset-uni.hbnf --backend=c > "$W/i2.c" 2> /dev/null
n=$((n + 1)); cmp -s "$W/i1.c" "$W/i2.c" || { echo "setlogic: FAIL (x ∈ ( ... ) is not what x in ( ... ) generates)"; fail=1; }
chk tests/setlogic/chain.hbnf "ok Tx;Qx;" "bad Qx;" "bad Tx;Ux;Qx;" "ok Tx;Ty;Uy;Qx;" "bad Tx;Ty;Uy;Qy;"
[ $fail = 0 ] && echo "setlogic: OK ($n results: in, not in, ∈, ∉ and the written set generate what ?, ?! and the longest-first choice do, in four backends where the grammar can go to them)"
exit $fail
