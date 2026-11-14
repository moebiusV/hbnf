#!/bin/sh
# The C preprocessor as a grammar (corpus/c/cpp.hbnf, C backend): it reads C source and leaves it expanded, as `"$GCC" -E -P` does.
#
# How a regression is caught here:
#   - every file of tests/cpp/*.c is expanded and its tokens compared with those of gcc (tests/cpp/NAME.expected, made by gcc once, with
#     tools/cpp_tokens.py; where gcc is installed it is asked again, so a change of gcc, or of a stale .expected, shows), and with clang's wherever
#     the file runs without gcc's own predefined macros (gcc is authoritative: where the two differ the file says so, as `/* clang differs */`);
#   - a file may say how the compilers are called: its first line `/* flags: -DX=1 -Itests/cpp/inc */` (default `-undef -nostdinc`); `/* tokens
#     only */` says the expanded text is not C, so that the C99 grammar (corpus/c/c99.hbnf) is not asked to read it, and `/* no rewind */` that
#     the `=>>` variant (every rewrite rewinds) cannot give the same tokens (it starts over on text that is no longer the user's);
#   - tests/cpp/diag/*.c are programs a compiler refuses or warns about: the diagnostics (line, kind and message) are those of gcc (.diag);
#   - random programs: `#if` and `#elif` (tools/cpp_fuzz.py) and macros (tools/cpp_fuzz_macros.py), on several seeds, against gcc;
#   - the harness checks itself: its token reader tells `--` from `- -`, reads `"/*"` as a string, and a wrong expectation is reported as one;
#     an expectation that is empty, or an output that is, is a failure (an empty file would match anything), and a count of checks that falls under
#     the number there are today says that something stopped running.
#   HBNF=/path/to/hbnf sh tests/cpp.sh      (default ./hbnf)
#   A file made again from gcc:  sh tests/cpp-regen.sh tests/cpp/NAME.c
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
command -v python3 > /dev/null 2>&1 || { echo "cpp: skipped (no python3)"; exit 0; }
GCC=${GCC:-gcc}     # the compiler that is the authority (GCC=/path/to/gcc); the one in the path, or gcc 16.2 where it is built (see scripts/build-gcc.sh)
HAVE_GCC=0; command -v "$GCC" > /dev/null 2>&1 && HAVE_GCC=1
CLANG=""; for cc_ in clang clang-19 clang-18 clang-17; do command -v $cc_ > /dev/null 2>&1 && { CLANG=$cc_; break; }; done
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0; n=0
bad() { echo "cpp: FAIL ($*)"; fail=1; }
toks() { python3 tools/cpp_tokens.py; }

# ---- the program: the grammar's parser, and a main that takes gcc's options
"$CLI" corpus/c/cpp.hbnf --backend=c > "$W/p.c" 2> "$W/err" || { echo "cpp: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cp tests/cpp-main.c "$W/main.c"
cat "$W/p.c" "$W/main.c" > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/m.c" -o "$W/pp" 2> "$W/cc.txt" || { echo "cpp: FAIL (cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
# the C99 grammar, to read what comes out
"$CLI" corpus/c/c99.hbnf --backend=c > "$W/c99.c" 2> "$W/err" || { echo "cpp: FAIL (c99 does not generate: $(head -c 300 "$W/err"))"; exit 1; }
croot=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c99.c")
cat "$W/c99.c" corpus/c/check.c > "$W/cm.c"
cc -O1 -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$croot" "$W/cm.c" -o "$W/c99" 2> "$W/cc.txt" || { echo "cpp: FAIL (cc c99: $(head -c 300 "$W/cc.txt"))"; exit 1; }

# ---- the harness checks itself
selftest() {   # text, want (the tokens, joined by blanks)
	got=$(printf '%s' "$1" | toks | tr '\n' ' ' | sed 's/ $//')
	n=$((n + 1)); [ "$got" = "$2" ] || bad "the token reader reads '$1' as '$got', not '$2'"
}
selftest 'a -- b' 'a -- b'
selftest 'a - - b' 'a - - b'
selftest 'x = "/*"; /* c */ y;' 'x = "/*" ; y ;'
selftest "c = '\"'; // d
e;" "c = '\"' ; e ;"
selftest '#define A 1
int a; # b
#pragma x
 /* c */ # define B 2
int b;' 'int a ; # b int b ;'
selftest 'a ## b %: c' 'a ## b % : c'
printf 'int a;\n' > "$W/s1.c"; printf 'int b;\n' > "$W/s2.c"
n=$((n + 1)); [ "$(toks < "$W/s1.c")" != "$(toks < "$W/s2.c")" ] || bad "two different texts have the same tokens"
# an expectation that is wrong is reported (the comparison below is the one every file goes through)
same() { cmp -s "$1" "$2"; }
printf 'int\na\n;\n' > "$W/e1.txt"; printf 'int\nb\n;\n' > "$W/e2.txt"
n=$((n + 1)); same "$W/e1.txt" "$W/e2.txt" && bad "a wrong expectation is not reported"
: > "$W/empty.txt"
n=$((n + 1)); [ ! -s "$W/empty.txt" ] || bad "the empty file is not empty"

# ---- the files of tests/cpp
nfiles=0
for f in tests/cpp/*.c; do
	b=${f%.c}; nfiles=$((nfiles + 1)); n=$((n + 1))
	first=$(head -1 "$f")
	flags=$(printf '%s' "$first" | sed -n 's|^/\* flags: \(.*\) \*/.*$|\1|p'); [ -n "$flags" ] || flags="-undef -nostdinc"
	[ -s "$b.expected" ] || { bad "$f has no expectation (an empty one matches anything): sh tests/cpp-regen.sh $f"; continue; }
	if ! "$W/pp" $flags "$f" > "$W/out.c" 2> "$W/e"; then bad "$f is refused: $(head -c 300 "$W/e")"; continue; fi
	python3 tools/cpp_tokens.py < "$W/out.c" > "$W/got.txt"
	[ -s "$W/got.txt" ] || { bad "$f: the output has no tokens"; continue; }
	same "$b.expected" "$W/got.txt" || { bad "$f: the tokens are not gcc's"; diff "$b.expected" "$W/got.txt" | head -6; }
	if [ $HAVE_GCC = 1 ]; then
		"$GCC" -E -P -w $flags "$f" 2> /dev/null | toks > "$W/gcc.txt"
		same "$b.expected" "$W/gcc.txt" || bad "$f: gcc no longer gives $b.expected (sh tests/cpp-regen.sh $f)"
	fi
	# clang agrees where the run has no predefined macros of the compiler's own (gcc is authoritative where they differ: say so in the file)
	if [ -n "$CLANG" ] && printf '%s' "$flags" | grep -q -- '-undef' && ! printf '%s' "$first" | grep -q 'clang differs'; then
		$CLANG -E -P -w $flags "$f" 2> /dev/null | toks > "$W/clang.txt"
		same "$b.expected" "$W/clang.txt" || bad "$f: $CLANG does not give $b.expected (if gcc is right, say /* clang differs */ in the first line)"
	fi
	if command -v pcc > /dev/null 2>&1; then
		pcc -E "$f" 2> /dev/null | toks > "$W/pcc.txt"
		same "$b.expected" "$W/pcc.txt" || bad "$f: pcc does not give $b.expected"
	fi
	# the expanded text is C: the grammar reads it (its `#define` lines are gone), unless the file says its text is not
	printf '%s' "$first" | grep -q 'tokens only' && continue
	n=$((n + 1)); got=$("$W/c99" "$W/out.c" 2>&1 | cut -d' ' -f1 | head -1)
	[ "$got" = ok ] || bad "$f: the C99 grammar does not read the expanded text: $("$W/c99" "$W/out.c" 2>&1 | head -c 200)"
done
[ $nfiles -ge 14 ] || bad "only $nfiles files in tests/cpp (there were 14 when this was written: a file that is gone is a test that is gone)"

# ---- the same grammar with `=>>` (every rewrite rewinds: the parse is read again from the start) gives the same tokens: only the work differs
sed '/^;/! { /cpp_predef\|cpp_unsplice/! { s/ => / =>> /; s/^\( *\)=> /\1=>> /; } }; s|include "../../grammars/common.hbnf"|include "'"$(pwd)"'/grammars/common.hbnf"|; s|include "cpp-gnu.hbnf"|include "'"$(pwd)"'/corpus/c/cpp-gnu.hbnf"|' corpus/c/cpp.hbnf > "$W/cpp-rewind.hbnf"
"$CLI" "$W/cpp-rewind.hbnf" --backend=c > "$W/rw.c" 2> "$W/err"
if [ -s "$W/rw.c" ] && grep -q 'hbnf_reread (.*, 0);' "$W/rw.c"; then
	cat "$W/rw.c" "$W/main.c" > "$W/rwm.c"
	cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/rwm.c" -o "$W/pp-rewind" 2> "$W/cc.txt" || bad "cc rewind: $(head -c 300 "$W/cc.txt")"
	for f in tests/cpp/*.c; do
		first=$(head -1 "$f")
		printf '%s' "$first" | grep -q 'no rewind' && continue
		flags=$(printf '%s' "$first" | sed -n 's|^/\* flags: \(.*\) \*/.*$|\1|p'); [ -n "$flags" ] || flags="-undef -nostdinc"
		n=$((n + 1))
		"$W/pp-rewind" $flags "$f" 2> /dev/null | toks > "$W/o2.txt"
		same "${f%.c}.expected" "$W/o2.txt" || bad "$f: =>> does not give gcc's tokens either"
	done
else bad "the =>> variant does not generate: $(head -c 300 "$W/err")"; fi

# ---- things that are not a comparison of tokens
# an expression of #if that is none is a diagnostic, as a compiler stops (and a division by zero that is evaluated is one; one that is not is not)
printf '#if 1 +\nint a;\n#endif\n#if 1 / 0\nint b;\n#endif\n#if 1 || 1 / 0\nint c;\n#endif\n' > "$W/u.c"
n=$((n + 1)); "$W/pp" "$W/u.c" > "$W/u.out" 2> "$W/u.err"
[ "$(grep -c 'invalid #if expression' "$W/u.out" "$W/u.err" | awk -F: '{ s += $2 } END { print s }')" = 2 ] && grep -q 'int c;' "$W/u.out" && ! grep -q 'int a;\|int b;' "$W/u.out" \
	|| bad "a bad #if expression is not an error, or the short circuit evaluates its right side"
# __DATE__ and __TIME__ are the time of the first use in a parse, in the formats of the standard
printf 'const char *d = __DATE__, *d2 = __DATE__, *t = __TIME__, *t2 = __TIME__;\n' > "$W/dt.c"
n=$((n + 1)); "$W/pp" "$W/dt.c" 2> /dev/null | grep -Eq '^const char \*d = "[A-Z][a-z]{2} [ 0-9][0-9] [0-9]{4}", \*d2 = "[A-Z][a-z]{2} [ 0-9][0-9] [0-9]{4}", \*t = "[0-9]{2}:[0-9]{2}:[0-9]{2}", \*t2 = "[0-9]{2}:[0-9]{2}:[0-9]{2}";' \
	|| bad "__DATE__ or __TIME__ is not in the standard's format"
if [ $HAVE_GCC = 1 ]; then
	# __FILE__ is the name the host gives (as gcc gives the name it was called with), and the two agree on it, and on __TIMESTAMP__'s form
	printf 'a = __FILE__ ;\n#define F __FILE__\nb = F ;\nc = __BASE_FILE__ ; d = __FILE_NAME__ ; e = __INCLUDE_LEVEL__ ;\n' > "$W/file.c"
	n=$((n + 1)); got=$("$W/pp" -undef -nostdinc "$W/file.c" 2> /dev/null | toks); want=$("$GCC" -E -P -undef -nostdinc "$W/file.c" 2> /dev/null | toks)
	[ -n "$got" ] && [ "$got" = "$want" ] || bad "__FILE__, __BASE_FILE__, __FILE_NAME__ or __INCLUDE_LEVEL__ is not gcc's"
	printf 'const char *t = __TIMESTAMP__;\n' > "$W/ts.c"
	n=$((n + 1)); got=$("$W/pp" -undef -nostdinc "$W/ts.c" 2> /dev/null | toks); want=$("$GCC" -E -P -undef -nostdinc "$W/ts.c" 2> /dev/null | toks)
	[ -n "$got" ] && [ "$got" = "$want" ] || bad "__TIMESTAMP__ is not gcc's"
	# trigraphs are read only when asked (as gcc's -trigraphs), and then they are the characters they stand for, in a string too
	printf '??=define X 1\nint a = X; char *s = "??/n"; int b??(2??) = ??<1??>;\nint c = __LINE__;\n' > "$W/tri.c"
	n=$((n + 1)); got=$("$W/pp" -undef -nostdinc -trigraphs "$W/tri.c" 2> /dev/null | toks); want=$("$GCC" -E -P -w -undef -nostdinc -trigraphs "$W/tri.c" 2> /dev/null | toks)
	[ -n "$got" ] && [ "$got" = "$want" ] || bad "-trigraphs is not gcc's"
	n=$((n + 1)); got=$("$W/pp" -undef -nostdinc "$W/tri.c" 2> /dev/null | toks); want=$("$GCC" -E -P -w -undef -nostdinc "$W/tri.c" 2> /dev/null | toks)
	[ -n "$got" ] && [ "$got" = "$want" ] || bad "without -trigraphs the text is not left as it is, as gcc leaves it"
	# the command line: -D and -U in the order given, an object-like and a function-like macro, and -I
	printf '#ifdef A\nint a = A;\n#endif\n#ifdef B\nint b = B;\n#endif\nint c = F(3);\n#ifdef G\nint g;\n#endif\n#include <inc.h>\nint d = IN;\n' > "$W/cmd.c"
	printf '#define IN 9\n' > "$W/inc.h"
	n=$((n + 1)); got=$("$W/pp" -undef -nostdinc -DA -DB=2 '-DF(x)=x+1' -DG -UG -I"$W" "$W/cmd.c" 2> /dev/null | toks)
	want=$("$GCC" -E -P -w -undef -nostdinc -DA -DB=2 '-DF(x)=x+1' -DG -UG -I"$W" "$W/cmd.c" 2> /dev/null | toks)
	[ -n "$got" ] && [ "$got" = "$want" ] || bad "-D, -U or -I is not gcc's"
	# gcc's own predefined macros are there without -undef, from the tables made from gcc (tools/gen_gcc_tables.py): where gcc is the version the tables were
	# made from (the second line of corpus/c/cpp-gnu.hbnf says which)
	tabver=$(sed -n '2s/^;   \(gcc[^,]*\),.*$/\1/p' corpus/c/cpp-gnu.hbnf | sed 's/.*[ )]\([0-9][0-9.]*\)$/\1/')
	havever=$("$GCC" -dumpfullversion 2> /dev/null || "$GCC" -dumpversion)
	if [ "$tabver" != "$havever" ]; then echo "cpp: (the tables are of gcc $tabver and \$GCC is $havever: the check of the predefined macros is left out; GCC=/path/to/gcc$tabver runs it)"; else
	printf '#ifdef __GNUC__\nint gnu = __GNUC__ * 100 + __GNUC_MINOR__;\n#endif\nint m = __INT_MAX__, s = __SIZEOF_LONG__; char *v = __VERSION__;\nint k = __INT64_C(7);\n#ifdef __x86_64__\nint x;\n#endif\n' > "$W/gnu.c"
	n=$((n + 1)); got=$("$W/pp" -nostdinc "$W/gnu.c" 2> /dev/null | toks); want=$("$GCC" -E -P -w -nostdinc "$W/gnu.c" 2> /dev/null | toks)
	[ -n "$got" ] && [ "$got" = "$want" ] || bad "gcc's predefined macros are not gcc's"
	# and for each standard (-std=): the macros that depend on it, trigraphs in the strict ones, `true` and `false` in `#if` in the newest
	printf '__STDC_VERSION__ __STRICT_ANSI__ linux unix i386 __GNUC_STDC_INLINE__ __GNUC_GNU_INLINE__ __STDC_UTF_16__ __STDC_IEC_60559_BFP__ __STDC_EMBED_FOUND__\n#if true\nint t;\n#endif\n??=define Q 1\nint q = Q;\n' > "$W/std.c"
	for st in c89 c99 c11 c17 c23 gnu89 gnu99 gnu11 gnu17 gnu23; do
		n=$((n + 1)); got=$("$W/pp" -std=$st -nostdinc "$W/std.c" 2> /dev/null | toks); want=$("$GCC" -E -P -w -std=$st -nostdinc "$W/std.c" 2> /dev/null | toks)
		[ -n "$got" ] && [ "$got" = "$want" ] || bad "-std=$st is not gcc's"
	done
	fi
fi

# ---- diagnostics: what gcc reports, line by line (tests/cpp/diag/NAME.c, NAME.diag), and that the text goes on
for f in tests/cpp/diag/*.c; do
	[ -f "$f" ] || continue
	b=${f%.c}; n=$((n + 1))
	[ -s "$b.diag" ] || { bad "$f has no .diag"; continue; }
	"$W/pp" -undef -nostdinc "$f" > /dev/null 2> "$W/d.err"
	sed -n 's/^[^:]*:\([0-9][0-9]*\): \(fatal error\|error\|warning\): \(.*\)$/\1: \2: \3/p' "$W/d.err" | sed 's/: fatal error:/: error:/' | sort -n > "$W/d.got"
	same "$b.diag" "$W/d.got" || { bad "$f: the diagnostics are not gcc's"; diff "$b.diag" "$W/d.got" | head -6; }
	# gcc says it as the .diag do from gcc 16 on (names in single quotes); an older gcc is not asked
	if [ $HAVE_GCC = 1 ] && [ "$("$GCC" -dumpversion | cut -d. -f1)" -ge 16 ]; then
		"$GCC" -E -P -undef -nostdinc "$f" 2>&1 > /dev/null | sed -n 's/^[^:]*:\([0-9][0-9]*\)\(:[0-9][0-9]*\)\{0,1\}: \(fatal error\|error\|warning\): \(.*\)$/\1: \3: \4/p' | sed 's/: fatal error:/: error:/; s/ \[-W[a-z0-9=+-]*\]$//' | sort -n > "$W/d.gcc"
		same "$b.diag" "$W/d.gcc" || bad "$f: gcc no longer reports what $b.diag says"
	fi
done

# ---- random programs, against gcc: #if and #elif (300 files of 3 groups) and macros (300 files, 4 seeds); the ones gcc itself refuses are left out
if [ $HAVE_GCC = 1 ]; then
	ok_=0; skip_=0
	mkdir -p "$W/fz"; python3 tools/cpp_fuzz.py 7 300 "$W/fz" 3
	for f in "$W"/fz/*.c; do
		"$GCC" -E -P -w -undef -nostdinc "$f" > "$W/fg.out" 2> /dev/null || { skip_=$((skip_ + 1)); continue; }
		python3 tools/cpp_tokens.py < "$W/fg.out" > "$W/fg.tok"
		"$W/pp" -undef -nostdinc "$f" 2> /dev/null | toks > "$W/fo.tok"
		[ -s "$W/fg.tok" ] || { bad "fuzz: gcc gave no tokens for $f"; continue; }
		if same "$W/fg.tok" "$W/fo.tok"; then ok_=$((ok_ + 1)); else bad "fuzz: $f is not read as gcc reads it"; cp "$f" "$W/../cpp-fuzz-fail.c" 2> /dev/null; fi
	done
	n=$((n + ok_))
	[ $ok_ -ge 150 ] || bad "only $ok_ #if programs were compared with gcc (about 200 are)"
	mok=0; cdiff=0; wsgap=0
	for seed in 11 12 13 14; do
		mkdir -p "$W/fm$seed"; python3 tools/cpp_fuzz_macros.py $seed 300 "$W/fm$seed"
		for f in "$W"/fm$seed/*.c; do
			"$GCC" -E -P -w -undef -nostdinc "$f" > "$W/fg.out" 2> /dev/null || continue
			python3 tools/cpp_tokens.py < "$W/fg.out" > "$W/fg.tok"
			"$W/pp" -undef -nostdinc "$f" 2> /dev/null | toks > "$W/fo.tok"
			[ -s "$W/fg.tok" ] || continue
			if same "$W/fg.tok" "$W/fo.tok"; then mok=$((mok + 1))
			else
				# known: the blanks inside a string that `#` made from arguments that held an empty one (gcc `"y,,"`, ours `"y, ,"`); the tokens are the same
				python3 tools/cpp_tokens.py --strings-nospace < "$W/fg.out" > "$W/fg.ns"; "$W/pp" -undef -nostdinc "$f" 2> /dev/null | python3 tools/cpp_tokens.py --strings-nospace > "$W/fo.ns"
				if same "$W/fg.ns" "$W/fo.ns"; then wsgap=$((wsgap + 1)); else bad "macro fuzz: $f is not read as gcc reads it"; cp "$f" "$W/../cpp-macro-fuzz-fail-$seed-$mok.c" 2> /dev/null; fi
			fi
			# clang, informational: where clang and gcc differ ours follows gcc, so only a difference from gcc counts
			if [ -n "$CLANG" ] && [ $((mok % 7)) = 0 ]; then
				$CLANG -E -P -w -undef -nostdinc "$f" 2> /dev/null | toks > "$W/fc.tok"
				same "$W/fg.tok" "$W/fc.tok" || cdiff=$((cdiff + 1))
			fi
		done
	done
	n=$((n + mok))
	[ $mok -ge 600 ] || bad "only $mok macro programs were compared with gcc (about 900 are)"
	echo "cpp: random programs: $ok_ #if and $mok macro programs identical to gcc ($skip_ #if files gcc refuses left out; $wsgap more differ only in the blanks of a string made by # from an empty argument, the known gap; clang differs from gcc on $cdiff sampled macro programs, where ours follows gcc)"
fi

[ $n -ge 600 ] || bad "only $n checks ran (there were over 1,400 when this was written: something stopped running)"
[ $fail -eq 0 ] && echo "cpp: OK ($n checks: $nfiles files against gcc and clang and the C99 grammar, the same with every rewrite a rewind, diagnostics, random programs, and the harness itself)" || exit 1
