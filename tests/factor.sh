#!/bin/sh
# Alternatives that begin with the same elements are read once.  tests/factor/ladder.hbnf is twelve levels of
# `e = x 1*( op x ) | x`: a parser that read x again for the bare alternative would take twice as long at each
# level, and parenthesised input such as ((((7)))) would not finish.  tests/factor/ladder-union.hbnf is the same
# ladder as a union (`/`), which must be accepted without a warning; the Rust, Zig and Ada parsers are
# built from them too, where those tools are installed.  Each line of tests/factor/cases.txt is a
# verdict (ok or bad) and an input; every one must come out as written, within five seconds.
#   HBNF=/path/to/hbnf sh tests/factor.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W" tests/factor/_r-*.hbnf' EXIT
fail=0; n=0
for g in ladder ladder-union; do
	"$CLI" tests/factor/$g.hbnf --backend=c > "$W/p.c" 2> "$W/err" \
		|| { echo "factor: FAIL ($g does not generate: $(head -c 300 "$W/err"))"; exit 1; }
	[ ! -s "$W/err" ] || { echo "factor: FAIL ($g warns: $(head -c 300 "$W/err"))"; fail=1; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
	cat "$W/p.c" corpus/c/check.c > "$W/m.c"
	${CC:-cc} -O1 -w -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$root" "$W/m.c" -o "$W/check" 2> "$W/cc.err" \
		|| { echo "factor: FAIL ($g does not compile: $(head -c 300 "$W/cc.err"))"; exit 1; }
	while IFS="$(printf '\t')" read -r want input; do
		n=$((n + 1))
		printf '%s' "$input" > "$W/in.txt"
		got=$(timeout 5 "$W/check" "$W/in.txt" 2> /dev/null | cut -d' ' -f1)
		[ -n "$got" ] || got=TIMEOUT
		[ "$got" = "$want" ] || { echo "factor: FAIL ($g: \`$input\` should be $want and is $got)"; fail=1; }
	done < tests/factor/cases.txt
done
# the same ladders through the Rust, Zig and Ada parsers, where the tools are installed: a parser that reads the
# shared beginning again at every level does not finish.  (The rules are renamed with letters: Rust and Zig name
# the entry type of the list in `e1` as they name the rule `e11`.)
REN='s/e12/el/g;s/e11/ek/g;s/e10/ej/g;s/e9/ei/g;s/e8/eh/g;s/e7/eg/g;s/e6/ef/g;s/e5/ee/g;s/e4/ed/g;s/e3/ec/g;s/e2/eb/g;s/e1/ea/g'
mkdir -p "$W/cases"; i=0
while IFS="$(printf '\t')" read -r want input; do
	i=$((i + 1)); printf '%s' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
done < tests/factor/cases.txt
nc=$i
verdicts() {   # BACKEND OUTPUT: every case has the verdict written for it
	k=1
	while [ $k -le $nc ]; do
		want=$(cat "$W/cases/c$k.want")
		got=$(grep -F "c$k.txt" "$2" | head -1 | cut -d' ' -f1)
		[ -n "$got" ] || got=TIMEOUT
		[ "$got" = "$want" ] || { echo "factor: FAIL ($g, $1: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
		k=$((k + 1))
	done
	n=$((n + nc))
}
for g in ladder ladder-union; do
	sed "$REN" tests/factor/$g.hbnf > tests/factor/_r-$g.hbnf       # beside the original: the include is relative
	if command -v rustc > /dev/null 2>&1; then
		d=$W/rs-$g; mkdir -p "$d"
		"$CLI" tests/factor/_r-$g.hbnf --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "factor: FAIL ($g does not generate for Rust)"; fail=1; }
		sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
		if (cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1); then
			timeout 120 "$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts rust "$d/out"
		else echo "factor: FAIL ($g does not compile for Rust: $(head -c 200 "$d/cc.txt"))"; fail=1; fi
	fi
	if command -v zig > /dev/null 2>&1; then
		d=$W/zg-$g; mkdir -p "$d"
		"$CLI" tests/factor/_r-$g.hbnf --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "factor: FAIL ($g does not generate for Zig)"; fail=1; }
		: > "$d/files.txt"; k=1
		while [ $k -le $nc ]; do
			cp "$W/cases/c$k.txt" "$d/f$k.dat"
			printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
			k=$((k + 1))
		done
		sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
		if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
			timeout 120 "$d/m" > "$d/out" 2>&1; verdicts zig "$d/out"
		else echo "factor: FAIL ($g does not compile for Zig: $(head -c 200 "$d/cc.txt"))"; fail=1; fi
	fi
	if command -v gnatmake > /dev/null 2>&1; then
		d=$W/ad-$g; mkdir -p "$d"
		"$CLI" tests/factor/_r-$g.hbnf --backend=ada --package=Lad > "$d/all.ada" 2> "$d/err" || { echo "factor: FAIL ($g does not generate for Ada)"; fail=1; }
		root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
		sed "s/MODULE/Lad/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
		if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
			timeout 120 "$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts ada "$d/out"
		else echo "factor: FAIL ($g does not compile for Ada: $(grep -m2 error "$d/cc.txt" | head -c 200))"; fail=1; fi
	fi
	rm -f tests/factor/_r-$g.hbnf
done
# the shared beginning is read once, in the code too: the bare alternative has no second read of the operand
if [ $fail = 0 ]; then
	echo "factor: OK ($n inputs through a twelve-level ladder of x 1*( op x ) | x, and of the same as a union, none slow; also Rust, Zig and Ada where installed)"
fi
exit $fail
