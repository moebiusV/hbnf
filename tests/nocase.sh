#!/bin/sh
# Case-insensitive literals of any length in a rule of characters (tests/nocase/words.hbnf): the scanner takes each
# letter in both cases at one position, so a long word is one branch and not one for each of its spellings.  Each
# line of tests/nocase/cases.txt is a verdict (ok or bad) and an input; every backend installed must give it.
#   HBNF=/path/to/hbnf sh tests/nocase.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
n=0; fail=0
mkdir -p "$W/cases"; i=0
while IFS="$(printf '\t')" read -r want input; do
	i=$((i + 1)); printf '%s' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
done < tests/nocase/cases.txt
nc=$i
verdicts() {   # BACKEND OUTPUT: every case has the verdict written for it
	k=1
	while [ $k -le $nc ]; do
		want=$(cat "$W/cases/c$k.want")
		got=$(grep -F "c$k.txt" "$2" | head -1 | cut -d' ' -f1)
		[ -n "$got" ] || got=none
		[ "$got" = "$want" ] || { echo "nocase: FAIL ($1: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
		k=$((k + 1))
	done
	n=$((n + 1))
}
G=tests/nocase/words.hbnf
t0=$(date +%s)
"$CLI" $G --backend=c > "$W/p.c" 2> "$W/err" || { echo "nocase: FAIL (does not generate for C: $(head -c 300 "$W/err"))"; exit 1; }
t1=$(date +%s)
[ $((t1 - t0)) -lt 10 ] || { echo "nocase: FAIL (generating took $((t1 - t0)) s)"; fail=1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/pm.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/pm.c" -o "$W/pcheck" 2> "$W/cc.err" || { echo "nocase: FAIL (C: $(head -c 300 "$W/cc.err"))"; exit 1; }
"$W/pcheck" "$W"/cases/c*.txt > "$W/p.out" 2>&1; verdicts c "$W/p.out"
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" $G --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "nocase: FAIL (does not generate for Rust: $(head -c 300 "$d/err"))"; fail=1; }
	sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
	if (cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts rust "$d/out"
	else echo "nocase: FAIL (Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" $G --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "nocase: FAIL (does not generate for Zig: $(head -c 300 "$d/err"))"; fail=1; }
	: > "$d/files.txt"; k=1
	while [ $k -le $nc ]; do
		cp "$W/cases/c$k.txt" "$d/f$k.dat"
		printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
		k=$((k + 1))
	done
	sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
		"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out"
	else echo "nocase: FAIL (Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" $G --backend=ada --package=Nc > "$d/all.ada" 2> "$d/err" || { echo "nocase: FAIL (does not generate for Ada: $(head -c 300 "$d/err"))"; fail=1; }
	root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
	sed "s/MODULE/Nc/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
	if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts ada "$d/out"
	else echo "nocase: FAIL (Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
fi
[ $fail = 0 ] && echo "nocase: OK ($nc inputs; C$( [ $n -gt 1 ] && echo " and $((n - 1)) more backend(s)"))"
exit $fail
