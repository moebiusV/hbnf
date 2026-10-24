#!/bin/sh
# The POSIX shell grammar (corpus/posix/shell.y): the generated C parser must accept every file
# in corpus/posix/tests/good and refuse every file in corpus/posix/tests/bad, and where dash is
# installed it must agree on each (dash -n is the reference).  The corpus is small and
# hand-written; scripts/posix-scan.sh runs the same comparison over every shell script on the
# machine and over mutations of them.
#   HBNF=/path/to/hbnf sh tests/posix.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=corpus/posix
GR=${POSIX_GRAMMAR:-shell.y}   # shell.y: the standard's yacc text read as it is; shell-native.hbnf: the same language written for hbnf

"$CLI" $D/$GR --backend=c > "$W/shell.c" 2> "$W/err" || { echo "posix: FAIL (generate)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/shell.c")
cat "$W/shell.c" $D/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w -DOUT_T="$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || { echo "posix: FAIL (cc)"; exit 1; }

fail=0; n=0
for kind in good bad; do
	for f in $D/tests/$kind/*.sh; do
		n=$((n + 1))
		got=$("$W/check" "$f" | cut -d' ' -f1)
		want=ok; [ $kind = bad ] && want=bad
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: $kind file, the parser says $got"; "$W/check" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
		if command -v dash > /dev/null 2>&1; then
			dash -n "$f" > /dev/null 2>&1; r=$?
			if { [ $kind = good ] && [ $r -ne 0 ]; } || { [ $kind = bad ] && [ $r -eq 0 ]; }; then
				echo "NOTE $f: dash -n disagrees with the file's directory (rc $r)"
			fi
		fi
	done
done
# The same files through the Rust, Zig and Ada parsers (the here-document scanner is written once for each).
verdicts() {   # verdicts BACKEND OUTPUT-FILE: every good file accepted, every bad one refused
	b=$1; out=$2; bad=0
	for kind in good bad; do
		for f in $D/tests/$kind/*.sh; do
			line=$(grep -F " $f" "$out" | head -1 | cut -d' ' -f1)
			want=ok; [ $kind = bad ] && want=bad
			if [ "$line" != "$want" ]; then echo "FAIL ($b) $f: $kind file, the parser says '$line'"; bad=$((bad + 1)); fi
		done
	done
	fail=$((fail + bad))
}
FILES="$D/tests/good/*.sh $D/tests/bad/*.sh"
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" $D/$GR --backend=rust > "$d/shell.rs" 2> /dev/null || { echo "FAIL (rust generate)"; fail=$((fail + 1)); }
	sed "s/MODULE/shell/g" $D/check.rs > "$d/m.rs"
	if (cd "$d" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1); then
		"$d/m" $FILES > "$d/out" 2>&1; verdicts rust "$d/out"
	else echo "FAIL (rust compile)"; head -5 "$d/cc.txt"; fail=$((fail + 1)); fi
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" $D/$GR --backend=zig > "$d/shell.zig" 2> /dev/null || { echo "FAIL (zig generate)"; fail=$((fail + 1)); }
	: > "$d/files.txt"; i=0
	for f in $FILES; do
		i=$((i + 1)); cp "$f" "$d/f$i.dat"
		printf '    .{ .name = "%s", .data = @embedFile("f%d.dat") },\n' "$f" "$i" >> "$d/files.txt"
	done
	sed "s/MODULE/shell.zig/g" $D/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if (cd "$d" && zig build-exe m.zig -femit-bin=m > cc.txt 2>&1); then
		"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out"
	else echo "FAIL (zig compile)"; head -5 "$d/cc.txt"; fail=$((fail + 1)); fi
fi
if command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" $D/$GR --backend=ada --package=Shell > "$d/all.ada" 2> /dev/null || { echo "FAIL (ada generate)"; fail=$((fail + 1)); }
	root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
	sed "s/MODULE/Shell/g; s/ROOT/$root/g" $D/check.adb > "$d/check.adb"
	if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
		"$d/m" $FILES > "$d/out" 2>&1; verdicts ada "$d/out"
	else echo "FAIL (ada compile)"; grep -m5 error "$d/cc.txt"; fail=$((fail + 1)); fi
fi
[ $fail = 0 ] && echo "posix: OK ($GR: $n files: the good accepted, the bad refused; C, and Rust, Zig, Ada where installed)" || { echo "posix: $fail FAIL"; exit 1; }
if [ -z "${POSIX_GRAMMAR:-}" ]; then POSIX_GRAMMAR=shell-native.hbnf sh "$0" || exit 1; fi
