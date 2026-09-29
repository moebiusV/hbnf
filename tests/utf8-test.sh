#!/bin/sh
# UTF-8 code-point matching: single-char multi-byte tokens and a multi-byte
# sequence (maximal munch across bytes).
#   HBNF_CLI=/path/to/hbnf_cli sh tests/utf8-test.sh      (default ./hbnf_cli)
set -u
cd "$(dirname "$0")/.."
CLI=${HBNF_CLI:-./hbnf_cli}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0

gen() { # grammar on stdin -> $W/t.c, sets ROOT
	cat > "$W/g.hbnf"
	if ! "$CLI" "$W/g.hbnf" --backend=c > "$W/t.c" 2> "$W/g.err"; then
		echo "GEN FAIL: $(tail -1 "$W/g.err")"; exit 1
	fi
	ROOT=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/t.c")
}

harness() { # compile $W/t.c with a main that runs parse_text on argv[1]
	cat "$W/t.c" > "$W/m.c"
	cat >> "$W/m.c" <<EOC
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    $ROOT out; char err[512]; size_t l = 0, c = 0;
    if (parse_text(argv[1], &out, err, sizeof err, &l, &c)) { printf("OK\n"); return 0; }
    printf("FAIL %zu:%zu %s\n", l, c, err); return 1;
}
EOC
	gcc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$W/m.c" -o "$W/t" || { echo "COMPILE FAIL"; exit 1; }
}

check() { # $1=expect(OK/FAIL) $2=input $3=label
	if "$W/t" "$2" > "$W/out" 2>&1; then got=OK; else got=FAIL; fi
	if [ "$got" = "$1" ]; then
		echo "  PASS [$3]: -> $got"
	else
		echo "  FAIL [$3]: -> $got (expected $1): $(cat "$W/out")"; rc=1
	fi
}

echo "== single-char multi-byte tokens =="
gen <<'G'
doc = 1*item
item = EURO | HIRAGANA | DIGIT | OTHER
EURO     = %u20AC
HIRAGANA = %u3042
DIGIT    = %x30-39
OTHER    = %x20-10FFFF
G
harness
check OK  "$(printf '\342\202\254\343\201\202\067')" "euro+hiragana+digit (\xc2\xac=U+20AC, \xe3\x81\x82=U+3042)"
check OK  "$(printf '\343\201\202\342\202\254')" "hiragana+euro"
check OK  "$(printf '\302\200')" "U+0080 (multi-byte, matches OTHER %x20-10FFFF)"
check FAIL "$(printf '\001')" "SOH control char (0x01 < 0x20)"
check FAIL "$(printf '\200')" "invalid UTF-8 (lone continuation byte 0x80)"

echo "== multi-byte sequence (maximal munch across bytes) =="
gen <<'G'
seq = EURO DIGIT
EURO  = %u20AC
DIGIT = %x30-39
G
harness
check OK   "$(printf '\342\202\254\067')" "euro+digit"
check FAIL "$(printf '\342\202\254')" "euro alone (digit required)"
check FAIL "$(printf '\342\202\254\343\201\202')" "euro+hiragana (not a digit)"
check FAIL "$(printf '\067\342\202\254')" "digit+euro (wrong order)"

echo "== alternation with a multi-code-point branch =="
gen <<'G'
doc = A | B C
A = %x41
B = %x42
C = %x43
G
harness
check OK   "A"     "A (the 1-code-point branch)"
check OK   "BC"    "BC (the 2-code-point branch, maximal munch)"
check FAIL "B"     "B alone (B C needs C)"
check FAIL "AB"    "A then a leftover B"
check FAIL "ABC"   "A then a leftover BC"

echo "== a reference to a multi-code-point rule =="
gen <<'G'
doc = PAIR PAIR
PAIR = A B
A = %x41
B = %x42
G
harness
check OK   "ABAB" "PAIR PAIR (A B A B, 4 code points)"
check FAIL "ABA"  "PAIR + A (3 code points, short)"
check FAIL "AB"   "PAIR alone (2 code points)"

echo "== ascii.hbnf still generates (no regression) =="
"$CLI" grammars/ascii.hbnf --backend=c > "$W/ascii.c" 2>&1 && echo "  PASS: ascii.hbnf generates"

exit $rc
