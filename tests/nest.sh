#!/bin/sh
# Alternatives that begin alike in a tree (tests/nest/trie.hbnf): the parser that reads each shared beginning once
# and the plain one (--no-factor) must agree on every input: the verdict, the message and the tree (written back
# out with --writer).  The Rust, Zig and Ada parsers, where those tools are installed, must give the same verdicts.
#   HBNF=/path/to/hbnf sh tests/nest.sh [N]      (default ./hbnf; N inputs, default 3000)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
N=${1:-3000}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0
python3 tests/nest/gen.py "$W/in" "$N" 7
for mode in fast plain; do
	flag=; [ $mode = plain ] && flag=--no-factor
	"$CLI" tests/nest/trie.hbnf --backend=c --writer $flag > "$W/$mode.c" 2> "$W/$mode.err" \
		|| { echo "nest: FAIL ($mode does not generate: $(head -c 300 "$W/$mode.err"))"; exit 1; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$mode.c")
	wr=$(sed -n 's/^static size_t write_\([A-Za-z0-9_]*\) (.*/\1/p' "$W/$mode.c" | head -1)
	cat "$W/$mode.c" tests/nest/dump.c > "$W/$mode-m.c"
	${CC:-cc} -O1 -w -std=gnu11 -D_GNU_SOURCE -include string.h "-DOUT_T=$root" "-DWRITE=write_$wr" "$W/$mode-m.c" -o "$W/$mode" 2> "$W/cc.err" \
		|| { echo "nest: FAIL ($mode does not compile: $(head -c 300 "$W/cc.err"))"; exit 1; }
	(cd "$W/in" && ls | sort -V | sed 's/^/in\//' > ../list; cd ..; xargs "$W/$mode" < list > "$W/$mode.out")
done
cmp -s "$W/fast.out" "$W/plain.out" || { echo "nest: FAIL (the fast and the plain parser differ: $(diff "$W/fast.out" "$W/plain.out" | head -4 | cut -c1-200 | tr '\n' ' '))"; fail=1; }
runs=$(grep -c 'run\|sfail' "$W/fast.c")
[ "$runs" -gt 0 ] || { echo "nest: FAIL (nothing is written out once)"; fail=1; }
# the trie of `fromto` has a run in a run: the second run of an alternation is numbered r2
grep -q 'sfail_r2_' "$W/fast.c" || { echo "nest: FAIL (no run in a run)"; fail=1; }
good=$(grep -c ' ok ' "$W/fast.out"); bad=$(grep -c ' bad ' "$W/fast.out")
[ "$good" -gt $((N / 4)) ] && [ "$bad" -gt $((N / 20)) ] || { echo "nest: FAIL (the inputs are not a mix: $good good, $bad bad)"; fail=1; }
# the same verdicts from the Rust, Zig and Ada parsers on the first inputs
NO=300
awk '{print $2}' "$W/fast.out" | head -$NO > "$W/want"
mkdir -p "$W/few"; i=1; while [ $i -le $NO ]; do cp "$W/in/c$i.txt" "$W/few/c$i.txt"; i=$((i + 1)); done
FEW=$(i=1; while [ $i -le $NO ]; do echo "$W/few/c$i.txt"; i=$((i + 1)); done)
check() {   # BACKEND OUTPUT: the verdict of each file, in order
	awk '{print $1}' "$2" | head -$NO > "$W/got-$1"
	cmp -s "$W/want" "$W/got-$1" || { echo "nest: FAIL ($1 gives other verdicts than C: $(paste "$W/want" "$W/got-$1" | awk '$1 != $2 {print NR ": C " $1 ", " FILENAME " " $2}' | head -3 | tr '\n' ' '))"; fail=1; }
}
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" tests/nest/trie.hbnf --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "nest: FAIL (does not generate for Rust)"; fail=1; }
	sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
	if (cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1); then
		"$d/m" $FEW > "$d/out" 2>&1; check rust "$d/out"
	else echo "nest: FAIL (does not compile for Rust: $(head -c 200 "$d/cc.txt"))"; fail=1; fi
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" tests/nest/trie.hbnf --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "nest: FAIL (does not generate for Zig)"; fail=1; }
	: > "$d/files.txt"; i=1
	while [ $i -le $NO ]; do
		cp "$W/few/c$i.txt" "$d/f$i.dat"
		printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $i $i >> "$d/files.txt"
		i=$((i + 1))
	done
	sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
		"$d/m" > "$d/out" 2>&1; check zig "$d/out"
	else echo "nest: FAIL (does not compile for Zig: $(head -c 200 "$d/cc.txt"))"; fail=1; fi
fi
if command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" tests/nest/trie.hbnf --backend=ada --package=Nst > "$d/all.ada" 2> "$d/err" || { echo "nest: FAIL (does not generate for Ada)"; fail=1; }
	root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
	sed "s/MODULE/Nst/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
	if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
		"$d/m" $FEW > "$d/out" 2>&1; check ada "$d/out"
	else echo "nest: FAIL (does not compile for Ada: $(grep -m2 error "$d/cc.txt" | head -c 200))"; fail=1; fi
fi
[ $fail = 0 ] && echo "nest: OK ($N inputs, $good good and $bad bad, agree on verdict, message and tree with the plain parse; Rust, Zig and Ada on the first $NO where installed)"
exit $fail
