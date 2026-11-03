#!/bin/sh
# The whitespace rule is scanned, and a rule of characters may hold more than a run of literals:
#   look.hbnf   a lookahead in it (`"$" !picture-start *~( CR | LF )`): a `$` line is blank space unless
#               it is a picture (`$BB**,***.**.`), the lookahead rule being read a character at a time
#   group.hbnf  a group of alternatives after a literal (`"$" ( %x53 | %x73 ) *~( CR | LF )`)
#   phrase.hbnf a whitespace rule that is not text: generation stops and says so, in every backend
# Each line of a grammar's cases file is a verdict (ok or bad) and an input (`\n` is a line end); every
# backend installed must give it.
#   HBNF=/path/to/hbnf sh tests/wslook.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
n=0; fail=0

# the grammar and its cases, in every backend installed
run() {   # NAME
	G=tests/wslook/$1.hbnf; C=tests/wslook/$1-cases.txt
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
			[ "$got" = "$want" ] || { echo "wslook: FAIL ($3, $1: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
			k=$((k + 1))
		done
		n=$((n + 1))
	}
	"$CLI" $G --backend=c > "$W/p.c" 2> "$W/err" || { echo "wslook: FAIL ($1 does not generate for C: $(head -c 300 "$W/err"))"; fail=1; return; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
	cat "$W/p.c" corpus/c/check.c > "$W/pm.c"
	cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror "-DOUT_T=$root" "$W/pm.c" -o "$W/pcheck" 2> "$W/cc.err" || { echo "wslook: FAIL ($1, C: $(head -c 300 "$W/cc.err"))"; fail=1; return; }
	"$W/pcheck" "$W"/cases/c*.txt > "$W/p.out" 2>&1; verdicts c "$W/p.out" $1
	if command -v rustc > /dev/null 2>&1; then
		d=$W/rs; rm -rf "$d"; mkdir -p "$d"
		"$CLI" $G --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "wslook: FAIL ($1 does not generate for Rust: $(head -c 300 "$d/err"))"; fail=1; }
		sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
		if (cd "$d" && rustc --edition 2021 -D unused-variables -A warnings -O -o m m.rs > cc.txt 2>&1); then
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts rust "$d/out" $1
		else echo "wslook: FAIL ($1, Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
	fi
	if command -v zig > /dev/null 2>&1; then
		d=$W/zg; rm -rf "$d"; mkdir -p "$d"
		"$CLI" $G --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "wslook: FAIL ($1 does not generate for Zig: $(head -c 300 "$d/err"))"; fail=1; }
		: > "$d/files.txt"; k=1
		while [ $k -le $nc ]; do
			cp "$W/cases/c$k.txt" "$d/f$k.dat"
			printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
			k=$((k + 1))
		done
		sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
		if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
			"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out" $1
		else echo "wslook: FAIL ($1, Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
	fi
	if command -v gnatmake > /dev/null 2>&1; then
		d=$W/ad; rm -rf "$d"; mkdir -p "$d"
		"$CLI" $G --backend=ada --package=Wl > "$d/all.ada" 2> "$d/err" || { echo "wslook: FAIL ($1 does not generate for Ada: $(head -c 300 "$d/err"))"; fail=1; }
		root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
		sed "s/MODULE/Wl/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
		if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts ada "$d/out" $1
		else echo "wslook: FAIL ($1, Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
	fi
}
run look
run group

# a whitespace rule that is not text stops generation, with the rule named, in every backend (not a crash, and not
# a parser that calls a scanner that is not there)
for b in c rust zig ada; do
	if "$CLI" tests/wslook/phrase.hbnf --backend=$b > "$W/o" 2> "$W/err"; then
		echo "wslook: FAIL (phrase.hbnf generated for $b)"; fail=1
	elif ! grep -q 'the whitespace rule `ws` is not a rule of characters' "$W/err" || grep -q 'raised' "$W/err"; then
		echo "wslook: FAIL (phrase.hbnf, $b: $(head -c 300 "$W/err"))"; fail=1
	fi
	n=$((n + 1))
done
[ $fail = 0 ] && echo "wslook: OK ($n results: two grammars in each backend installed, and the whitespace rule that is not text in four)"
exit $fail
