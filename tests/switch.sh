#!/bin/sh
# Switching grammars: `=> grammar(x)` at the end of an alternative makes the grammar `x` (an
# `include "f" as x`) the current one, and it stays until the next switch.  tests/switch/calc.hbnf is a
# calculator whose `>>FIXED` and `>>FREE` lines change the white space skipped between tokens (blanks and
# line ends, or blanks only), whose `>>MODE name` names the grammar by the text it matched, and which has
# a guess whose switch has to be undone.  Each line of cases.txt is a verdict (ok or bad) and an input
# (`\n` is a line end).  Then the messages.  Backends that generate a switch: BACKENDS; the others must
# refuse it.
#   HBNF=/path/to/hbnf sh tests/switch.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W" tests/switch/_m' EXIT
n=0; fail=0
mkdir -p "$W/cases"; i=0
while IFS="$(printf '\t')" read -r want input; do
	i=$((i + 1)); printf '%b' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
done < tests/switch/cases.txt
nc=$i
verdicts() {   # BACKEND OUTPUT: every case has the verdict written for it
	k=1
	while [ $k -le $nc ]; do
		want=$(cat "$W/cases/c$k.want")
		got=$(grep -F "c$k.txt" "$2" | head -1 | cut -d' ' -f1)
		[ -n "$got" ] || got=none
		[ "$got" = "$want" ] || { echo "switch: FAIL ($1: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
		k=$((k + 1))
	done
	n=$((n + 1))
}
H=tests/switch/calc.hbnf
BACKENDS=${BACKENDS:-c rust zig ada}
has() { case " $BACKENDS " in *" $1 "*) return 0 ;; esac; return 1; }
"$CLI" $H --backend=c > "$W/p.c" 2> "$W/err" || { echo "switch: FAIL (does not generate for C: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/pm.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/pm.c" -o "$W/pcheck" 2> "$W/cc.err" || { echo "switch: FAIL (C: $(head -c 300 "$W/cc.err"))"; exit 1; }
"$W/pcheck" "$W"/cases/c*.txt > "$W/p.out" 2>&1; verdicts c "$W/p.out"
if has rust && command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" $H --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "switch: FAIL (does not generate for Rust: $(head -c 300 "$d/err"))"; fail=1; }
	sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
	if (cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts rust "$d/out"
	else echo "switch: FAIL (Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if has zig && command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" $H --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "switch: FAIL (does not generate for Zig: $(head -c 300 "$d/err"))"; fail=1; }
	: > "$d/files.txt"; k=1
	while [ $k -le $nc ]; do
		cp "$W/cases/c$k.txt" "$d/f$k.dat"
		printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
		k=$((k + 1))
	done
	sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
		"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out"
	else echo "switch: FAIL (Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if has ada && command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" $H --backend=ada --package=Sw > "$d/all.ada" 2> "$d/err" || { echo "switch: FAIL (does not generate for Ada: $(head -c 300 "$d/err"))"; fail=1; }
	root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
	sed "s/MODULE/Sw/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
	if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts ada "$d/out"
	else echo "switch: FAIL (Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
fi
[ $fail = 0 ] || exit 1
# The unknown name is told with the grammars there are.
printf '>>MODE nosuch 1;' > "$W/nosuch.txt"
"$W/pcheck" "$W/nosuch.txt" > "$W/nosuch.out" 2>&1
grep -qF 'a grammar: fixed, free' "$W/nosuch.out" || { echo "switch: FAIL (unknown grammar name: $(head -c 300 "$W/nosuch.out"))"; fail=1; }

refuse() {   # NAME WANT [BACKEND]: the grammar in tests/switch/_m/g.hbnf is refused with a message containing WANT
	if "$CLI" tests/switch/_m/g.hbnf --backend="${3:-c}" > /dev/null 2> "$W/err"; then
		echo "switch: FAIL ($1: generated, should be refused)"; fail=1
	elif ! grep -qF -- "$2" "$W/err"; then
		echo "switch: FAIL ($1: the message lacks \`$2\`: $(head -c 400 "$W/err"))"; fail=1
	fi
}
mkdir -p tests/switch/_m
sed 's#\.\./\.\./#../../../#' tests/switch/free.hbnf > tests/switch/_m/free.hbnf
sed 's#\.\./\.\./#../../../#' tests/switch/fixed.hbnf > tests/switch/_m/fixed.hbnf
inc='prefix none\ninclude "free.hbnf" as free\n'
printf "${inc}top = \"a\" => grammar(nosuch)\n" > tests/switch/_m/g.hbnf
refuse "an unknown grammar" 'no grammar is included `as nosuch`'
refuse "an unknown grammar, the known ones" 'the grammars included `as` here are: free'
printf "${inc}top = \"a\" => 0\n" > tests/switch/_m/g.hbnf
refuse "a value after =>" 'are not built yet'
printf "${inc}top = \"a\" => grammar(mode)\n" > tests/switch/_m/g.hbnf
refuse "a tag that is not bound" 'no earlier `%as mode`'
printf "${inc}top = [ \"a\" ] => grammar(free)\n" > tests/switch/_m/g.hbnf
refuse "a switch that can match no text" 'can match no text'
# a rule the grammar replaces besides white space
printf 'prefix none\ninclude "o.hbnf" as dia\nname = "y"\ntop = name "a" => grammar(dia)\n' > tests/switch/_m/g.hbnf
printf 'prefix none\nwhitespace none\nname = "z"\n' > tests/switch/_m/o.hbnf
refuse "a rule replaced besides white space" 'replaces white space only so far'
# the other backends
printf "${inc}top = \"a\" => grammar(free)\n" > tests/switch/_m/g.hbnf
for b in rust zig ada; do
	has $b || refuse "$b without a switch" 'backend does not yet' $b
done
refuse "tree-sitter" 'tree-sitter has one fixed set of rules and one `extras`' tree-sitter
[ $fail = 0 ] || exit 1
echo "switch: OK (white space changed by a switch, a tag naming the grammar, a guess undone, a pending token after a switch, in $n backend(s); the messages)"
