#!/bin/sh
# `x where (col = 6)` (CONTEXTS.md section 24): a test of the column the element before it starts in, in a phrase rule and in a rule of
# characters (a scanner), in the C, Rust, Zig and Ada backends: tests/column/records.hbnf is built and each line of tests/column/cases.txt (ok or bad, TAB, the text;
# `\n` is a line end) is read.  A condition that is not about `col` is refused with what is allowed, and the corpus/cobol/cobol-fixed.hbnf
# programs (tests/cobol.sh) use it on a real format.
#   HBNF=/path/to/hbnf sh tests/column.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
command -v cc > /dev/null 2>&1 || { echo "column: skipped (no C compiler)"; exit 0; }
fail=0; n=0
G=tests/column/records.hbnf
"$CLI" $G --backend=c > "$W/p.c" 2> "$W/err" || { echo "column: FAIL (does not generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/m.c" -o "$W/check" 2> "$W/cc.txt" || { echo "column: FAIL (the C does not compile: $(head -c 300 "$W/cc.txt"))"; exit 1; }
while IFS="$(printf '\t')" read -r want text; do
	n=$((n + 1)); printf '%b' "$text" > "$W/t.txt"
	got=$("$W/check" "$W/t.txt" | cut -d' ' -f1)
	[ "$got" = "$want" ] || { echo "column: FAIL ([$text] should be $want and is $got)"; fail=1; }
done < tests/column/cases.txt
# the other backends write the same test: Rust is built and run on the same cases where rustc is installed; Zig and Ada are
# generated (they were run by hand, in the container, on the same cases: tests/column.sh cannot, without zig and gnatmake)
for b in rust zig ada; do
	"$CLI" $G --backend=$b --package=Tc > "$W/o.$b" 2> "$W/err" \
		|| { echo "column: FAIL ($b does not generate it: $(head -c 300 "$W/err"))"; fail=1; }
done
if command -v rustc > /dev/null 2>&1 && [ -s "$W/o.rust" ]; then
	mkdir -p "$W/rs"; cp "$W/o.rust" "$W/rs/l.rs"; sed "s/MODULE/l/g" corpus/c/check.rs > "$W/rs/m.rs"
	if (cd "$W/rs" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1); then
		while IFS="$(printf '\t')" read -r want text; do
			n=$((n + 1)); printf '%b' "$text" > "$W/t.txt"
			got=$("$W/rs/m" "$W/t.txt" | cut -d' ' -f1)
			[ "$got" = "$want" ] || { echo "column: FAIL (Rust: [$text] should be $want and is $got)"; fail=1; }
		done < tests/column/cases.txt
	else echo "column: FAIL (the Rust parser does not compile: $(grep -m2 error "$W/rs/cc.txt" | head -c 300))"; fail=1; fi
fi
# fixed-format COBOL (a rule of characters that repeats a rule holding a position test: the Iter atom) generates in each backend;
# tests/cobol.sh builds and runs it
for b in rust zig ada; do
	"$CLI" corpus/cobol/cobol-fixed.hbnf --root=compilation-group --backend=$b --package=Tc > /dev/null 2> "$W/err" \
		|| { echo "column: FAIL (fixed-format COBOL does not generate in $b: $(grep -v warning "$W/err" | head -c 300))"; fail=1; }
done
refuse() {   # NAME TEXT WANT: a grammar with TEXT as its rule is refused with a message containing WANT
	printf 'prefix none\nwhitespace none\ntop = %s\n' "$2" > "$W/r.hbnf"
	if "$CLI" "$W/r.hbnf" --backend=c > /dev/null 2> "$W/err"; then
		echo "column: FAIL ($1: generated, should be refused)"; fail=1
	elif ! grep -qF -- "$3" "$W/err"; then
		echo "column: FAIL ($1: the message lacks \`$3\`: $(head -c 300 "$W/err"))"; fail=1
	fi
}
refuse "a name that is not col" '"a" where (column = 3)' 'is not `col` or a number'
refuse "no comparison" '"a" where (col)' 'a comparison is missing'
refuse "a missing )" '"a" where ((col = 3)' 'the condition ends with `)`'
refuse "nothing to test" 'where (col = 3) "a"' 'follows the element it tests'
refuse "something after the condition" '"a" where (col = 3 col)' 'is not part of a condition'
[ $fail = 0 ] || exit 1
echo "column: OK ($n cases in a phrase rule and a rule of characters, in C and Rust (Zig and Ada generate); the bad conditions are refused with what is allowed)"
