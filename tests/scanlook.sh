#!/bin/sh
# A rule of characters that holds a lookahead is scanned in C (tests/scanlook/scan.hbnf: `*Char !any`, `1*( !( "<" | "&" ) any )`,
# `till(T) := *( !T any )`, `quoted(C)`), where it used to be read a character at a time, a tree node for each, with a warning:
#   - every case of scan-cases.txt (a verdict, ok or bad, and an input; `\nnn` is an octal byte) gets its verdict from the parser
#     of every backend installed (Rust, Zig and Ada read the rules a character at a time still, and must agree);
#   - for C there is no warning, and the rules are scanned: the generated parser calls a scanner for them;
#   - for the others the warning is still there, saying what to write instead.
#   HBNF=/path/to/hbnf sh tests/scanlook.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
n=0; fail=0

# the grammar and its cases, in every backend installed
run() {   # NAME
	G=tests/scanlook/$1.hbnf; C=tests/scanlook/$1-cases.txt
	rm -rf "$W/cases"; mkdir -p "$W/cases"; i=0
	while IFS="$(printf '\t')" read -r want input; do
		i=$((i + 1)); printf '%b' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
	done < "$C"
	nc=$i
	verdicts() {   # BACKEND OUTPUT: every case has the verdict written for it
		k=1
		while [ $k -le $nc ]; do
			want=$(cat "$W/cases/c$k.want")
			got=$(grep -F "c$k.txt" "$2" | head -1 | cut -d' ' -f1)
			[ -n "$got" ] || got=none
			[ "$got" = "$want" ] || { echo "scanlook: FAIL ($3, $1: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
			k=$((k + 1))
		done
		n=$((n + 1))
	}
	"$CLI" $G --backend=c > "$W/p.c" 2> "$W/err" || { echo "scanlook: FAIL ($1 does not generate for C: $(head -c 300 "$W/err"))"; fail=1; return; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
	cat "$W/p.c" corpus/c/check.c > "$W/pm.c"
	cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror "-DOUT_T=$root" "$W/pm.c" -o "$W/pcheck" 2> "$W/cc.err" || { echo "scanlook: FAIL ($1, C: $(head -c 300 "$W/cc.err"))"; fail=1; return; }
	"$W/pcheck" "$W"/cases/c*.txt > "$W/p.out" 2>&1; verdicts c "$W/p.out" $1
	if command -v rustc > /dev/null 2>&1; then
		d=$W/rs; rm -rf "$d"; mkdir -p "$d"
		"$CLI" $G --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "scanlook: FAIL ($1 does not generate for Rust: $(head -c 300 "$d/err"))"; fail=1; }
		sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
		if (cd "$d" && rustc --edition 2021 -D unused-variables -A warnings -O -o m m.rs > cc.txt 2>&1); then
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts rust "$d/out" $1
		else echo "scanlook: FAIL ($1, Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
	fi
	if command -v zig > /dev/null 2>&1; then
		d=$W/zg; rm -rf "$d"; mkdir -p "$d"
		"$CLI" $G --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "scanlook: FAIL ($1 does not generate for Zig: $(head -c 300 "$d/err"))"; fail=1; }
		: > "$d/files.txt"; k=1
		while [ $k -le $nc ]; do
			cp "$W/cases/c$k.txt" "$d/f$k.dat"
			printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
			k=$((k + 1))
		done
		sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
		if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
			"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out" $1
		else echo "scanlook: FAIL ($1, Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
	fi
	if command -v gnatmake > /dev/null 2>&1; then
		d=$W/ad; rm -rf "$d"; mkdir -p "$d"
		"$CLI" $G --backend=ada --package=Sl > "$d/all.ada" 2> "$d/err" || { echo "scanlook: FAIL ($1 does not generate for Ada: $(head -c 300 "$d/err"))"; fail=1; }
		root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
		sed "s/MODULE/Sl/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
		if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts ada "$d/out" $1
		else echo "scanlook: FAIL ($1, Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
	fi
}
run scan

# C: no warning, and a scanner for the rule that holds the lookahead (a rule read a character at a time has none), with the
# functions it calls for what repeats inside it
"$CLI" tests/scanlook/scan.hbnf --backend=c > "$W/c.c" 2> "$W/c.err"
if grep -q 'keeps it from being one token' "$W/c.err"; then
	echo "scanlook: FAIL (C warns that a rule with a lookahead is read a character at a time: $(head -c 300 "$W/c.err"))"; fail=1
fi
for r in top; do
	grep -q "^static size_t scan_[a-z]*_*$r(" "$W/c.c" || { echo "scanlook: FAIL (C has no scanner for $r)"; fail=1; }
done
n=$((n + 1))
# and the other backends say it, as they did
for b in rust zig ada; do
	"$CLI" tests/scanlook/scan.hbnf --backend=$b > "$W/o" 2> "$W/err"
	[ "$(grep -c 'keeps it from being one token' "$W/err")" -ge 4 ] \
		|| { echo "scanlook: FAIL ($b does not warn that a rule with a lookahead is read a character at a time)"; fail=1; }
	n=$((n + 1))
done
[ $fail = 0 ] && echo "scanlook: OK ($n results: one grammar, its cases in each backend installed, C scanned and the others warning)"
exit $fail
