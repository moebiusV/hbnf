#!/bin/sh
# The C preprocessor as a grammar (corpus/c/cpp.hbnf, C backend): it reads C source and leaves it expanded (object-like and function-like
# macros, conditional groups; the text after the last rewrite is the result).  Each program of tests/cpp is expanded and its tokens are
# compared with those of `gcc -E -P` (tests/cpp/NAME.expected, made by gcc once; where gcc is installed it is asked again, so a change
# of gcc shows).  What the grammar does not read yet (`#if` with an expression) is refused, and the expanded text is read by the C99
# grammar.
#   HBNF=/path/to/hbnf sh tests/cpp.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
command -v python3 > /dev/null 2>&1 || { echo "cpp: skipped (no python3)"; exit 0; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" corpus/c/cpp.hbnf --backend=c > "$W/p.c" 2> "$W/err" || { echo "cpp: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat > "$W/main.c" <<'EOM'
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); static char buf[1 << 20]; size_t n = fread(buf, 1, sizeof buf - 1, f); buf[n] = 0; fclose(f);
    OUT_T tree; char err[2048]; size_t l, c;
    memset(&tree, 0, sizeof tree);
    if (parse_text(buf, &tree, err, sizeof err, &l, &c)) { fputs(hbnf_rr_buf ? hbnf_rr_buf : buf, stdout); return 0; }
    fprintf(stderr, "bad\n%s\n", err); return 1;
}
EOM
cat "$W/p.c" "$W/main.c" > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/m.c" -o "$W/pp" 2> "$W/cc.txt" || { echo "cpp: FAIL (cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
# the C99 grammar, to read what comes out
"$CLI" corpus/c/c99.hbnf --backend=c > "$W/c99.c" 2> "$W/err" || { echo "cpp: FAIL (c99 does not generate: $(head -c 300 "$W/err"))"; exit 1; }
croot=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c99.c")
cat "$W/c99.c" corpus/c/check.c > "$W/cm.c"
cc -O1 -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$croot" "$W/cm.c" -o "$W/c99" 2> "$W/cc.txt" || { echo "cpp: FAIL (cc c99: $(head -c 300 "$W/cc.txt"))"; exit 1; }
fail=0; n=0
for f in tests/cpp/*.c; do
	b=${f%.c}; n=$((n + 1))
	if ! "$W/pp" "$f" > "$W/out.c" 2> "$W/e"; then echo "cpp: FAIL ($f is refused: $(head -c 300 "$W/e"))"; fail=1; continue; fi
	python3 tools/cpp_tokens.py < "$W/out.c" > "$W/got.txt"
	cmp -s "$b.expected" "$W/got.txt" || { echo "cpp: FAIL ($f: the tokens are not gcc's)"; diff "$b.expected" "$W/got.txt" | head -6; fail=1; }
	if command -v gcc > /dev/null 2>&1; then
		gcc -E -P -undef -nostdinc "$f" 2> /dev/null | python3 tools/cpp_tokens.py > "$W/gcc.txt"
		cmp -s "$b.expected" "$W/gcc.txt" || { echo "cpp: FAIL ($f: gcc no longer gives $b.expected)"; fail=1; }
	fi
	# clang gives the same tokens (the grammar is to match gcc and clang, and pcc where it is installed)
	for cc_ in clang clang-19 clang-18; do
		command -v $cc_ > /dev/null 2>&1 || continue
		$cc_ -E -P -undef -nostdinc "$f" 2> /dev/null | python3 tools/cpp_tokens.py > "$W/clang.txt"
		cmp -s "$b.expected" "$W/clang.txt" || { echo "cpp: FAIL ($f: $cc_ does not give $b.expected)"; fail=1; }
		break
	done
	if command -v pcc > /dev/null 2>&1; then
		pcc -E "$f" 2> /dev/null | python3 tools/cpp_tokens.py > "$W/pcc.txt"
		cmp -s "$b.expected" "$W/pcc.txt" || { echo "cpp: FAIL ($f: pcc does not give $b.expected)"; fail=1; }
	fi
	# the expanded text is C: the grammar reads it (its `#define` lines are white space to it)
	n=$((n + 1)); got=$("$W/c99" "$W/out.c" 2>&1 | cut -d' ' -f1 | head -1)
	[ "$got" = ok ] || { echo "cpp: FAIL ($f: the C99 grammar does not read the expanded text: $("$W/c99" "$W/out.c" 2>&1 | head -c 200))"; fail=1; }
done
# the same grammar with `=>>` (rewrites that rewind: the parse is read again from the start) gives the same tokens: only the work differs
sed '/^;/! s/ => / =>> /; /^;/! s/^\( *\)=> /\1=>> /; s|include "../../grammars/common.hbnf"|include "'"$(pwd)"'/grammars/common.hbnf"|' corpus/c/cpp.hbnf > "$W/cpp-rewind.hbnf"
"$CLI" "$W/cpp-rewind.hbnf" --backend=c > "$W/rw.c" 2> "$W/err"
if [ -s "$W/rw.c" ] && grep -q 'hbnf_reread (.*, 0);' "$W/rw.c"; then
	cat "$W/rw.c" "$W/main.c" > "$W/rwm.c"
	cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/rwm.c" -o "$W/pp-rewind" 2> "$W/cc.txt" || { echo "cpp: FAIL (cc rewind: $(head -c 300 "$W/cc.txt"))"; fail=1; }
	for f in tests/cpp/*.c; do
		n=$((n + 1))
		"$W/pp-rewind" "$f" 2> /dev/null | python3 tools/cpp_tokens.py > "$W/o2.txt"
		cmp -s "${f%.c}.expected" "$W/o2.txt" || { echo "cpp: FAIL ($f: =>> does not give gcc's tokens either)"; fail=1; }
	done
else echo "cpp: FAIL (the =>> variant does not generate: $(head -c 300 "$W/err"))"; fail=1; fi
# an expression that is none is left as an #error, as a compiler stops (and a division by zero that is evaluated is one; one that is not is not)
printf '#if 1 +\nint a;\n#endif\n#if 1 / 0\nint b;\n#endif\n#if 1 || 1 / 0\nint c;\n#endif\n' > "$W/u.c"
n=$((n + 1)); "$W/pp" "$W/u.c" > "$W/u.out" 2>&1
[ "$(grep -c '#error invalid #if expression' "$W/u.out")" = 2 ] && grep -q 'int c;' "$W/u.out" && ! grep -q 'int a;\|int b;' "$W/u.out" \
	|| { echo "cpp: FAIL (a bad #if expression is not left as an #error, or the short circuit evaluates its right side)"; fail=1; }
# random #if and #elif programs, against gcc (where installed): 300 files of 3 groups; the ones gcc itself refuses are left out
if command -v gcc > /dev/null 2>&1; then
	mkdir -p "$W/fz"; python3 tools/cpp_fuzz.py 7 300 "$W/fz" 3
	ok_=0; skip_=0
	for f in "$W"/fz/*.c; do
		gcc -E -P -w -undef -nostdinc "$f" > "$W/fg.out" 2> /dev/null || { skip_=$((skip_ + 1)); continue; }
		python3 tools/cpp_tokens.py < "$W/fg.out" > "$W/fg.tok"
		"$W/pp" "$f" 2> /dev/null | python3 tools/cpp_tokens.py > "$W/fo.tok"
		if cmp -s "$W/fg.tok" "$W/fo.tok"; then ok_=$((ok_ + 1)); else echo "cpp: FAIL (fuzz: $f is not read as gcc reads it)"; cp "$f" "$W/../cpp-fuzz-fail.c" 2> /dev/null; fail=1; fi
	done
	n=$((n + ok_))
fi
[ $fail -eq 0 ] && echo "cpp: OK ($n checks: macros, #if / #elif expressions and conditional groups expanded as gcc -E -P does (and 300 random #if files), and the result read by the C99 grammar)" || exit 1
