#!/bin/sh
# The C11 grammar (corpus/c/c11.hbnf), C backend: the generated parser must accept every file in
# corpus/c/tests/good and refuse every file in corpus/c/tests/bad, and where gcc is installed it
# must agree (gcc -fsyntax-only is the reference).  scripts/c-scan.sh runs the same comparison over
# any directory of C sources, preprocessed.  The grammar uses the typedef context, which the C, Rust and
# Zig backends have (Ada follows); the same files go through the Rust and Zig parsers where installed.
#   HBNF=/path/to/hbnf sh tests/c.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=corpus/c

"$CLI" $D/c11.hbnf --backend=c > "$W/c11.c" 2> "$W/err" || { echo "c: FAIL (generate)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c11.c")
cat "$W/c11.c" $D/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || { echo "c: FAIL (cc)"; exit 1; }

fail=0; n=0
for kind in good bad; do
	for f in $D/tests/$kind/*.c; do
		n=$((n + 1))
		got=$("$W/check" "$f" | cut -d' ' -f1)
		want=ok; [ $kind = bad ] && want=bad
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: $kind file, the parser says $got"; "$W/check" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
		if command -v gcc > /dev/null 2>&1; then
			gcc -fsyntax-only -std=gnu11 -w "$f" > /dev/null 2>&1; r=$?
			if { [ $kind = good ] && [ $r -ne 0 ]; } || { [ $kind = bad ] && [ $r -eq 0 ]; }; then
				echo "NOTE $f: gcc -fsyntax-only disagrees with the file's directory (rc $r)"
			fi
		fi
	done
done
verdicts() {   # verdicts BACKEND OUTPUT-FILE: every good file accepted, every bad one refused
	b=$1; out=$2
	for kind in good bad; do
		for f in $D/tests/$kind/*.c; do
			line=$(grep -F " $f" "$out" | head -1 | cut -d' ' -f1)
			want=ok; [ $kind = bad ] && want=bad
			if [ "$line" != "$want" ]; then echo "FAIL ($b) $f: $kind file, the parser says '$line'"; fail=$((fail + 1)); fi
		done
	done
}
FILES="$D/tests/good/*.c $D/tests/bad/*.c"
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" $D/c11.hbnf --backend=rust > "$d/c11.rs" 2> /dev/null || { echo "FAIL (rust generate)"; fail=$((fail + 1)); }
	sed "s/MODULE/c11/g" $D/check.rs > "$d/m.rs"
	if (cd "$d" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1); then
		"$d/m" $FILES > "$d/out" 2>&1; verdicts rust "$d/out"
	else echo "FAIL (rust compile)"; head -5 "$d/cc.txt"; fail=$((fail + 1)); fi
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" $D/c11.hbnf --backend=zig > "$d/c11.zig" 2> /dev/null || { echo "FAIL (zig generate)"; fail=$((fail + 1)); }
	: > "$d/files.txt"; i=0
	for f in $FILES; do
		i=$((i + 1)); cp "$f" "$d/f$i.dat"
		printf '    .{ .name = "%s", .data = @embedFile("f%d.dat") },\n' "$f" "$i" >> "$d/files.txt"
	done
	sed "s/MODULE/c11.zig/g" $D/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if (cd "$d" && zig build-exe m.zig -femit-bin=m > cc.txt 2>&1); then
		"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out"
	else echo "FAIL (zig compile)"; head -5 "$d/cc.txt"; fail=$((fail + 1)); fi
fi
[ $fail = 0 ] && echo "c: OK ($n files: the good accepted, the bad refused; C, and Rust and Zig where installed)" || { echo "c: $fail FAIL"; exit 1; }
