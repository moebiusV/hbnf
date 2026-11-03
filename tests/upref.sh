#!/bin/sh
# Up references: `$k^` is the capture k of the nearest enclosing rule that kept it with `x as k`, and `$k^R`
# the capture of the enclosing rule R.  An up reference is an implicit parameter, worked out when the grammar is
# read: every rule between the rule that keeps k and the rule that holds the `$k^` is passed the text (its
# offset and length, in the frame of numbers that `%col` and `x %num j` already use).  Each line of a cases
# file is a verdict, ok or bad, and an input; the parser of every backend installed must give it.  Then: a
# fixed literal (`"ADD" as k ... scope-end`) is read as the hyperrule `scope-end("ADD")`, the same parser as when
# it is written that way; a plain `$t` in a group, an option or a lookahead (rules of their own) works too;
# and the refusals: tests/upref/bad_NAME.hbnf is refused with a message that contains bad_NAME.want, whole.
#   HBNF=/path/to/hbnf sh tests/upref.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
n=0; fail=0
# parsers GRAMMAR CASES BACKENDS: the parser of GRAMMAR in each of the backends listed (those
# installed), run on the inputs of CASES (\n in an input is a line feed).
parsers() {
	g=$1; cases=$2; list=$3; t=$(basename "$g" .hbnf)
	rm -rf "$W/cases"; mkdir -p "$W/cases"; i=0
	while IFS="$(printf '\t')" read -r want input; do
		i=$((i + 1)); printf '%b' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
	done < "$cases"
	nc=$i
	for b in $list; do
		d=$W/$t-$b; mkdir -p "$d"
		case $b in
		c)    command -v cc > /dev/null 2>&1 || continue ;;
		rust) command -v rustc > /dev/null 2>&1 || continue ;;
		zig)  command -v zig > /dev/null 2>&1 || continue ;;
		ada)  command -v gnatmake > /dev/null 2>&1 || continue ;;
		esac
		if [ $b = ada ]; then
			"$CLI" "$g" --backend=ada --package=Lk > "$d/all.ada" 2> "$d/err"
		else
			"$CLI" "$g" --backend=$b > "$d/p.$b" 2> "$d/err"
		fi || { echo "upref: FAIL ($t does not generate for $b: $(head -c 300 "$d/err"))"; fail=1; continue; }
		case $b in
		c)
			root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$d/p.c")
			cat "$d/p.c" corpus/c/check.c > "$d/m.c"
			cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$d/m.c" -o "$d/m" 2> "$d/cc.txt" \
				|| { echo "upref: FAIL ($t, C does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		rust)
			sed "s/MODULE/p/g" corpus/c/check.rs > "$d/m.rs"; mv "$d/p.rust" "$d/p.rs"
			(cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1) \
				|| { echo "upref: FAIL ($t, Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		zig)
			: > "$d/files.txt"; k=1
			while [ $k -le $nc ]; do
				cp "$W/cases/c$k.txt" "$d/f$k.dat"
				printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
				k=$((k + 1))
			done
			mv "$d/p.zig" "$d/l.zig"
			sed "s/MODULE/l.zig/g" corpus/c/check.zig \
				| awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
			(cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1) \
				|| { echo "upref: FAIL ($t, Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" > "$d/out" 2>&1 ;;
		ada)
			root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
			sed "s/MODULE/Lk/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
			(cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1) \
				|| { echo "upref: FAIL ($t, Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		esac
		k=1
		while [ $k -le $nc ]; do
			want=$(cat "$W/cases/c$k.want")
			got=$(grep -F "c$k.txt" "$d/out" | head -1 | cut -d' ' -f1)
			[ -n "$got" ] || got=none
			[ "$got" = "$want" ] || { echo "upref: FAIL ($t, $b: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
			k=$((k + 1))
		done
		n=$((n + 1))
	done
}



ALL="c rust zig ada"
parsers tests/upref/deep.hbnf tests/upref/deep-cases.txt "$ALL"
parsers tests/upref/nested.hbnf tests/upref/nested-cases.txt "$ALL"
parsers tests/upref/two.hbnf tests/upref/two-cases.txt "$ALL"
parsers tests/upref/two-nocase.hbnf tests/upref/two-nocase-cases.txt "$ALL"
parsers tests/upref/named.hbnf tests/upref/named-cases.txt "$ALL"
parsers tests/upref/fence.hbnf tests/upref/fence-cases.txt "$ALL"
parsers tests/upref/fence-named.hbnf tests/upref/fence-cases.txt "$ALL"
parsers tests/upref/group.hbnf tests/upref/group-cases.txt "$ALL"
parsers tests/upref/look.hbnf tests/upref/look-cases.txt "$ALL"
parsers tests/upref/static.hbnf tests/upref/static-cases.txt "$ALL"
parsers tests/upref/fold-up.hbnf tests/upref/fold-up-cases.txt "$ALL"

# A fixed literal: the helper becomes scope-end("ADD") and the like, and the parser is the one the
# hyperrule gives; no number is passed at run time.
for b in c rust zig ada; do
	"$CLI" tests/upref/static.hbnf --backend=$b --package=Lk > "$W/s.$b" 2> "$W/err" \
		|| { echo "upref: FAIL (static.hbnf for $b: $(head -c 300 "$W/err"))"; fail=1; continue; }
	"$CLI" tests/upref/static-explicit.hbnf --backend=$b --package=Lk > "$W/e.$b" 2> "$W/err" \
		|| { echo "upref: FAIL (static-explicit.hbnf for $b: $(head -c 300 "$W/err"))"; fail=1; continue; }
	cmp -s "$W/s.$b" "$W/e.$b" || { echo "upref: FAIL (static.hbnf and static-explicit.hbnf differ in $b)"; fail=1; }
done
grep -q 'HF(' "$W/s.c" && { echo "upref: FAIL (static.hbnf passes a number at run time)"; fail=1; }
grep -q '"END-ADD"' "$W/s.c" || { echo "upref: FAIL (static.hbnf has no END-ADD literal)"; fail=1; }
# A text kept by a rule is passed at run time.
"$CLI" tests/upref/deep.hbnf --backend=c > "$W/deep.c" 2> "$W/err" || { echo "upref: FAIL (deep.hbnf: $(head -c 300 "$W/err"))"; fail=1; }
grep -q 'HF(' "$W/deep.c" || { echo "upref: FAIL (deep.hbnf passes nothing in the frame)"; fail=1; }

for f in tests/upref/bad_*.hbnf; do
	k=$(basename "$f" .hbnf)
	want=$(head -1 "tests/upref/$k.want")
	if "$CLI" "$f" --backend=c > /dev/null 2> "$W/$k.err"; then
		echo "upref: FAIL ($k: accepted)"; fail=1
	elif ! grep -qF -- "$want" "$W/$k.err"; then
		echo "upref: FAIL ($k: message was: $(head -c 400 "$W/$k.err"))"; fail=1
	fi
done
[ $fail = 0 ] || exit 1
echo "upref: OK (\$k^ and \$k^R in $n parser(s): the nearest binder, a binder named, two levels down, two binders of one helper, the fence, a group, a lookahead; a fixed literal is a hyperrule; the refusals)"
