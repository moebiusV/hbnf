#!/bin/sh
# Wire grammars (RFCPLAN.md step 7b): rules of bit fields read into a parser over
# a buffer of bits, in C and Rust, checked on fixed byte fixtures.
#   HBNF=/path/to/hbnf sh tests/wire.sh      (default ./hbnf)
set -u
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
CC=${CC:-gcc}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0
GEN_FLAGS=

# check NAME: generate tests/wire/NAME.hbnf, build it with tests/wire/NAME_main.c,
# and compare the program's output with tests/wire/NAME.expected.
check() {
	n=$1; libs=${2:-}; need=${3:-}; g=${4:-$n}; flags=${5:--Wall -Wextra -Werror}; gen=${6:-}
	if [ -n "$need" ] && ! printf '#include <%s>\n' "$need" | $CC -E - > /dev/null 2>&1; then
		echo "SKIP $n: no <$need>; its actions call the system's library"; return
	fi
	if ! "$CLI" tests/wire/$g.hbnf --backend=c $gen > "$T/$g.c" 2> "$T/$n.err"; then
		echo "FAIL $n: generation: $(cat "$T/$n.err")"; fail=$((fail+1)); return
	fi
	if ! $CC $flags -I"$T" -Icorpus/bip39 -o "$T/$n" tests/wire/${n}_main.c $libs 2> "$T/$n.cc"; then
		echo "FAIL $n: cc"; cat "$T/$n.cc"; fail=$((fail+1)); return
	fi
	"$T/$n" > "$T/$n.out" 2>&1
	if cmp -s "$T/$n.out" tests/wire/$n.expected; then
		echo "PASS $n"
	else
		echo "FAIL $n: output differs"; diff "$T/$n.out" tests/wire/$n.expected | head -20
		fail=$((fail+1))
	fi
}

# check_rust NAME [GRAMMAR [EXPECTED]]: the same grammar through the Rust backend,
# a Rust driver (tests/wire/NAME_main.rs, `mod GRAMMAR;`), the same expected output.
check_rust() {
	n=$1; g=${2:-$n}; want=${3:-$n}; link=${4:-}
	command -v rustc > /dev/null 2>&1 || { echo "SKIP $n (rust): no rustc"; return; }
	if [ -n "$link" ] && [ -z "$(ls /usr/lib*/lib$link.so* /lib*/lib$link.so* /usr/lib/*/lib$link.so* 2>/dev/null | head -1)" ]; then
		echo "SKIP $n (rust): no lib$link; its code calls the system's library"; return
	fi
	d=$T/rs_$n; mkdir -p "$d"
	if ! "$CLI" tests/wire/$g.hbnf --backend=rust $GEN_FLAGS > "$d/$g.rs" 2> "$d/err"; then
		echo "FAIL $n (rust): generation: $(cat "$d/err")"; fail=$((fail+1)); return
	fi
	cp tests/wire/${n}_main.rs "$d/main.rs"
	if ! rustc --edition 2021 ${link:+-C link-arg=-l:$(basename $(ls /usr/lib*/lib$link.so* /lib*/lib$link.so* /usr/lib/*/lib$link.so* 2>/dev/null | head -1))} -o "$d/main" "$d/main.rs" 2> "$d/rustc"; then
		echo "FAIL $n (rust): rustc"; head -30 "$d/rustc"; fail=$((fail+1)); return
	fi
	"$d/main" > "$d/out" 2>&1
	if cmp -s "$d/out" tests/wire/$want.expected; then
		echo "PASS $n (rust)"
	else
		echo "FAIL $n (rust): output differs"; diff "$d/out" tests/wire/$want.expected | head -20
		fail=$((fail+1))
	fi
}

# check_zig NAME [GRAMMAR [EXPECTED]]: the same grammar through the Zig backend,
# a Zig driver (tests/wire/NAME_main.zig, `@import("GRAMMAR.zig")`), the same expected output.
check_zig() {
	n=$1; g=${2:-$n}; want=${3:-$n}
	command -v zig > /dev/null 2>&1 || { echo "SKIP $n (zig): no zig"; return; }
	d=$T/zg_$n; mkdir -p "$d"
	if ! "$CLI" tests/wire/$g.hbnf --backend=zig $GEN_FLAGS > "$d/$g.zig" 2> "$d/err"; then
		echo "FAIL $n (zig): generation: $(cat "$d/err")"; fail=$((fail+1)); return
	fi
	cp tests/wire/${n}_main.zig "$d/main.zig"
	if ! (cd "$d" && zig build-exe main.zig -femit-bin=main > zig.out 2>&1); then
		echo "FAIL $n (zig): zig"; head -30 "$d/zig.out"; fail=$((fail+1)); return
	fi
	"$d/main" > "$d/out" 2>&1
	if cmp -s "$d/out" tests/wire/$want.expected; then
		echo "PASS $n (zig)"
	else
		echo "FAIL $n (zig): output differs"; diff "$d/out" tests/wire/$want.expected | head -20
		fail=$((fail+1))
	fi
}

# check_ada NAME [GRAMMAR [EXPECTED]]: the same grammar through the Ada backend, which
# writes the package specification and body in one file (gnatchop splits it), and an
# Ada driver (tests/wire/NAME_main.adb, `with GRAMMAR_PACKAGE`), the same expected output.
check_ada() {
	n=$1; g=${2:-$n}; want=${3:-$n}; pkg=${4:-Net}
	command -v gnatmake > /dev/null 2>&1 || { echo "SKIP $n (ada): no gnatmake"; return; }
	d=$T/ad_$n; mkdir -p "$d"
	if ! "$CLI" tests/wire/$g.hbnf --backend=ada --package=$pkg $GEN_FLAGS > "$d/all.ada" 2> "$d/err"; then
		echo "FAIL $n (ada): generation: $(cat "$d/err")"; fail=$((fail+1)); return
	fi
	cp tests/wire/${n}_main.adb "$d/"
	if ! (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 ${n}_main.adb -o main > gnat.out 2>&1); then
		echo "FAIL $n (ada): gnat"; head -30 "$d/gnat.out"; fail=$((fail+1)); return
	fi
	"$d/main" > "$d/out" 2>&1
	if cmp -s "$d/out" tests/wire/$want.expected; then
		echo "PASS $n (ada)"
	else
		echo "FAIL $n (ada): output differs"; diff "$d/out" tests/wire/$want.expected | head -20
		fail=$((fail+1))
	fi
}

# expect_error NAME TEXT: the grammar is refused with a message containing TEXT.
expect_error() {
	n=$1; want=$2
	if "$CLI" tests/wire/reject/$n.hbnf --backend=c > "$T/rej.out" 2> "$T/rej.err"; then
		echo "FAIL reject/$n: accepted"; fail=$((fail+1)); return
	fi
	if grep -qF -- "$want" "$T/rej.err"; then
		echo "PASS reject/$n"
	else
		echo "FAIL reject/$n: message was: $(cat "$T/rej.err")"; fail=$((fail+1))
	fi
}

check net
check_rust net
check_rust segwit
check_rust mnemonic mnemonic_rust mnemonic_ports crypto
check_rust mixed
check_rust mixed2
check_rust mixed3
check_rust mixed4 mixed4 mixed4_zig
check_rust mixed6 mixed6_rust mixed6
check_rust mixed5 mixed5_rust mixed5
GEN_FLAGS=--writer
check_rust mixed7 mixed mixed7
GEN_FLAGS=
check_rust segwit_in segwit_in segwit_in
check_zig net
check_zig segwit
check_zig mnemonic mnemonic_zig mnemonic_ports
check_zig mixed
check_zig mixed2
check_zig mixed3
check_zig mixed4 mixed4 mixed4_zig
check_zig mixed6 mixed6_zig mixed6
check_zig mixed5 mixed5_zig mixed5
GEN_FLAGS=--writer
check_zig mixed7 mixed mixed7
GEN_FLAGS=
check_zig segwit_in segwit_in segwit_in
check_ada net
check_ada segwit segwit segwit Segwit
check_ada mnemonic mnemonic_ada mnemonic_ports Mnemonic
check_ada mixed mixed mixed_ada Mixed
check_ada mixed2 mixed2 mixed2_ada Mixed2
check_ada mixed3 mixed3 mixed3_ada Mixed3
check_ada mixed4 mixed4 mixed4_ada Mixed4
check_ada mixed6 mixed6_ada mixed6 Mixed6
check_ada mixed5 mixed5_ada mixed5 Mixed5
GEN_FLAGS=--writer
check_ada mixed7 mixed mixed7 Mixed
GEN_FLAGS=
check_ada segwit_in segwit_in segwit_in_ada Segwit_In
check net_cbuf "" "" net
# Text and bit rules in one grammar (the generated text parser is not -Wextra clean)
check mixed "" "" mixed -w
check mixed2 "" "" mixed2 -w
check mixed3 "" "" mixed3 -w
check mixed4 "" "" mixed4 -w
check mixed7 "" "" mixed -w --writer
check mixed5 "" "" mixed5 -w
check mixed6 "" "" mixed6 -w
check segwit "" "" segwit -w
check mnemonic -lcrypto openssl/sha.h mnemonic -w

# bip39: the word lists (RFCPLAN.md step 7b's acceptance test).  Every word of
# every official list parses to its line number; English also against the
# published vectors.
for lang in chinese_simplified chinese_traditional czech english french \
            italian japanese korean portuguese spanish; do
	list=corpus/bip39/wordlists/$lang.txt
	d=$T/bip39_$lang; mkdir -p "$d"
	sed "s|bip39/english.hbnf|bip39/$lang.hbnf|" tests/wire/bip39_one.hbnf \
		> "$d/one.hbnf"
	sed -i "s|\"../../grammars|\"$(pwd)/grammars|" "$d/one.hbnf"
	if ! "$CLI" "$d/one.hbnf" --backend=c > "$d/one.c" 2> "$d/err"; then
		echo "FAIL bip39 $lang: generation: $(head -c 300 "$d/err")"
		fail=$((fail+1)); continue
	fi
	{
		printf '#include <stdio.h>\n#include "one.c"\n'
		printf 'static const char *w[] = {\n'
		sed 's/.*/"&",/' "$list"
		printf '};\nint main(void) {\n    int bad = 0;\n'
		printf '    for (int i = 0; i < 2048; i++) {\n'
		printf '        one_t out; char err[256]; size_t line, col;\n'
		printf '        if (!parse_text(w[i], &out, err, sizeof err, &line, &col)'
		printf ' || (int)out != i) {\n'
		printf '            if (bad++ < 3) printf("word %%d (%%s) is read as %%d\\n", i, w[i], (int)out);\n'
		printf '        }\n    }\n'
		printf '    if (!bad) printf("2048 words at their index\\n");\n'
		printf '    return bad != 0;\n}\n'
	} > "$d/main.c"
	if ! $CC -w -I"$d" -o "$d/main" "$d/main.c" 2> "$d/cc"; then
		echo "FAIL bip39 $lang: cc: $(head -c 300 "$d/cc")"
		fail=$((fail+1)); continue
	fi
	if "$d/main" > "$d/out" 2>&1; then
		echo "PASS bip39 $lang: $(cat "$d/out")"
	else
		echo "FAIL bip39 $lang: $(cat "$d/out")"; fail=$((fail+1))
	fi
done

d=$T/bip39_phrase; mkdir -p "$d"
sed "s|\"../../grammars|\"$(pwd)/grammars|" tests/wire/bip39_phrase.hbnf > "$d/p.hbnf"
if "$CLI" "$d/p.hbnf" --backend=c > "$d/bip39_phrase.c" 2> "$d/err" \
   && $CC -w -I"$d" -o "$d/m" tests/wire/bip39_phrase_main.c 2> "$d/cc"; then
	"$d/m" > "$d/out" 2>&1; sed 's/^/    /' "$d/out"
	if grep -q FAIL "$d/out"; then fail=$((fail+1)); else echo "PASS bip39 vectors"; fi
else
	echo "FAIL bip39 vectors: $(head -c 300 "$d/err" "$d/cc")"; fail=$((fail+1))
fi
expect_error offset "says bit 5, but the fields above it end at bit 4"
expect_error offset_order "the place comes before the width"
expect_error unknown_field "is not a number read before this point"
expect_error recursive "contains itself"
expect_error too_wide "fields are 1 to 64 bits"
expect_error keyword "is a C keyword"
expect_error odd_little "little-endian needs a whole number of octets"
expect_error bare_decimal "a bare number"
expect_error undefined "is not a rule in this file"
[ "$fail" -eq 0 ] && echo "wire OK" || { echo "wire: $fail FAIL"; exit 1; }
