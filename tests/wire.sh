#!/bin/sh
# Wire grammars (RFCPLAN.md step 7b): a `binary` file read into a C parser over
# a byte buffer, checked on fixed byte fixtures.
#   HBNF=/path/to/hbnf sh tests/wire.sh      (default ./hbnf)
set -u
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
CC=${CC:-gcc}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0

# check NAME: generate tests/wire/NAME.hbnf, build it with tests/wire/NAME_main.c,
# and compare the program's output with tests/wire/NAME.expected.
check() {
	n=$1; libs=${2:-}; need=${3:-}
	if [ -n "$need" ] && ! printf '#include <%s>\n' "$need" | $CC -E - > /dev/null 2>&1; then
		echo "SKIP $n: no <$need>; its actions call the system's library"; return
	fi
	if ! "$CLI" tests/wire/$n.hbnf --backend=c > "$T/$n.c" 2> "$T/$n.err"; then
		echo "FAIL $n: generation: $(cat "$T/$n.err")"; fail=$((fail+1)); return
	fi
	if ! $CC -Wall -Wextra -Werror -I"$T" -Icorpus/bip39 -o "$T/$n" tests/wire/${n}_main.c $libs 2> "$T/$n.cc"; then
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
check segwit
check mnemonic -lcrypto openssl/sha.h

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
expect_error hyphen "has a hyphen"
expect_error unknown_field "is not a number read before this point"
expect_error recursive "contains itself"
expect_error too_wide "fields are 1 to 64 bits"
expect_error keyword "is a C keyword"
expect_error odd_little "little-endian needs a whole number of octets"
expect_error bare_decimal "a bare decimal number has no width"
expect_error undefined "is not a rule in this file"
[ "$fail" -eq 0 ] && echo "wire OK" || { echo "wire: $fail FAIL"; exit 1; }
