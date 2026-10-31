#!/bin/sh
# Lookahead: `!x` and `&x` test what is next without consuming it.  The
# parser of tests/lookahead/look.hbnf reads  a: b;  as a label and  a := b;
# as an assignment although both start with a colon; the output must be
# tests/lookahead/expected.txt.
#   HBNF=/path/to/hbnf sh tests/lookahead.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/lookahead/look.hbnf --backend=c --ast > "$W/c.c" 2> "$W/err" \
    || { echo "lookahead: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
cat "$W/c.c" tests/lookahead/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/look" \
    2> "$W/cc.txt" || { echo "lookahead: FAIL (compile)"; head -8 "$W/cc.txt"; exit 1; }
"$W/look" > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/lookahead/expected.txt; then
	echo "lookahead: FAIL"; diff -u tests/lookahead/expected.txt "$W/got.txt" | head -30; exit 1
fi

# A lookahead over rules that are phrases (tests/lookahead/phrase.hbnf), in every backend installed: each
# line of phrase-cases.txt is a verdict (ok or bad) and an input.
n=0; fail=0
mkdir -p "$W/cases"; i=0
while IFS="$(printf '\t')" read -r want input; do
	i=$((i + 1)); printf '%s' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
done < tests/lookahead/phrase-cases.txt
nc=$i
verdicts() {   # BACKEND OUTPUT: every case has the verdict written for it
	k=1
	while [ $k -le $nc ]; do
		want=$(cat "$W/cases/c$k.want")
		got=$(grep -F "c$k.txt" "$2" | head -1 | cut -d' ' -f1)
		[ -n "$got" ] || got=none
		[ "$got" = "$want" ] || { echo "lookahead: FAIL (phrase, $1: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
		k=$((k + 1))
	done
	n=$((n + 1))
}
"$CLI" tests/lookahead/phrase.hbnf --backend=c > "$W/p.c" 2> "$W/err" || { echo "lookahead: FAIL (phrase does not generate for C: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/pm.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/pm.c" -o "$W/pcheck" 2> "$W/cc.err" || { echo "lookahead: FAIL (phrase, C: $(head -c 300 "$W/cc.err"))"; exit 1; }
"$W/pcheck" "$W"/cases/c*.txt > "$W/p.out" 2>&1; verdicts c "$W/p.out"
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" tests/lookahead/phrase.hbnf --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "lookahead: FAIL (phrase does not generate for Rust: $(head -c 300 "$d/err"))"; fail=1; }
	sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
	if (cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts rust "$d/out"
	else echo "lookahead: FAIL (phrase, Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" tests/lookahead/phrase.hbnf --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "lookahead: FAIL (phrase does not generate for Zig: $(head -c 300 "$d/err"))"; fail=1; }
	: > "$d/files.txt"; k=1
	while [ $k -le $nc ]; do
		cp "$W/cases/c$k.txt" "$d/f$k.dat"
		printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
		k=$((k + 1))
	done
	sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
		"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out"
	else echo "lookahead: FAIL (phrase, Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" tests/lookahead/phrase.hbnf --backend=ada --package=Lk > "$d/all.ada" 2> "$d/err" || { echo "lookahead: FAIL (phrase does not generate for Ada: $(head -c 300 "$d/err"))"; fail=1; }
	root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
	sed "s/MODULE/Lk/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
	if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts ada "$d/out"
	else echo "lookahead: FAIL (phrase, Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
fi
[ $fail = 0 ] || exit 1
echo "lookahead: OK (a colon and a :=; a lookahead over phrase rules in $n backend(s))"
