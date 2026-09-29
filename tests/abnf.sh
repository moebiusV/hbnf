#!/bin/sh
# RFC 5234 forms the reader takes (RFCPLAN.md step 1): `/` between single
# characters, `=/`, `%d13.10`, `*m`, continuation by indentation, newlines
# inside ( ), `sensitivity`, <prose-val>, and core.hbnf.  Each grammar is
# generated as C, compiled, and run on inputs it must accept or reject;
# the schemas it must refuse are checked for the reason given.
#   HBNF_CLI=/path/to/hbnf_cli sh tests/abnf.sh      (default ./hbnf_cli)
set -u
cd "$(dirname "$0")/.."
CLI=${HBNF_CLI:-./hbnf_cli}
HERE=$(pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0

gen_file() { # schema file -> $W/t, a program that parses argv[1]
	if ! "$CLI" "$1" --backend=c > "$W/t.c" 2> "$W/g.err"; then
		echo "  FAIL: $1 does not generate: $(head -1 "$W/g.err")"; rc=1; return 1
	fi
	ROOT=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/t.c")
	cat "$W/t.c" > "$W/m.c"
	cat >> "$W/m.c" <<EOC
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    $ROOT out; char err[512]; size_t l = 0, c = 0;
    if (parse_text(argv[1], &out, err, sizeof err, &l, &c)) { printf("OK\n"); return 0; }
    printf("FAIL %zu:%zu %s\n", l, c, err); return 1;
}
EOC
	gcc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$W/m.c" -o "$W/t" \
	    || { echo "  FAIL: $1 does not compile"; rc=1; return 1; }
}

gen() { # grammar on stdin
	cat > "$W/g.hbnf"
	gen_file "$W/g.hbnf"
}

check() { # $1=expect(OK/FAIL) $2=input $3=label
	[ -x "$W/t" ] || return
	if "$W/t" "$2" > "$W/out" 2>&1; then got=OK; else got=FAIL; fi
	if [ "$got" = "$1" ]; then
		echo "  PASS [$3]: -> $got"
	else
		echo "  FAIL [$3]: -> $got (expected $1): $(cat "$W/out")"; rc=1
	fi
}

refuse() { # $1=text the message must hold, $2=label; grammar on stdin
	cat > "$W/bad.hbnf"
	refuse_file "$W/bad.hbnf" "$1" "$2"
}

refuse_file() { # $1=schema file, $2=text the message must hold, $3=label
	if "$CLI" "$1" --backend=c > /dev/null 2> "$W/err.txt"; then
		echo "  FAIL [$3]: accepted"; rc=1; return
	fi
	if grep -q -- "$2" "$W/err.txt"; then
		echo "  PASS [$3]: refused"
	else
		echo "  FAIL [$3]: $(head -1 "$W/err.txt")"; rc=1
	fi
}

CORE="$HERE/grammars/core.hbnf"

echo "== \`/\` between single characters =="
rm -f "$W/t"; gen <<G
include "$CORE"
doc  = 1*item
item = DIGIT / ALPHA
G
check OK   "a1B" "letters and digits"
check FAIL "-"   "neither"
refuse "is ABNF.s union" "/ between phrases" <<'G'
doc = "a" "b" / "c"
G

echo "== newlines inside ( ), and a rule going on to an indented line =="
rm -f "$W/t"; gen <<G
include "$CORE"
doc = 1*( DIGIT
        / ALPHA )
G
check OK   "x9" "a group across lines"
rm -f "$W/t"; gen <<'G'
doc = A
      B   ; the rule goes on here
A = %x41
B = %x42
G
check OK   "AB" "A, then B on the next line"
check FAIL "A"  "A alone"

echo "== =/ =="
rm -f "$W/t"; gen <<G
include "$CORE"
doc = 1*hex
hex = DIGIT
hex =/ %x61-66
G
check OK   "12af" "decimal and a-f"
check FAIL "g"    "g"
rm -f "$W/t"; gen_file tests/abnf/extend.hbnf
check OK   "0aF" "=/ on an included rule; the root stays doc"
check FAIL "g"   "g"
refuse "which no .=. before it defines" "=/ with no = before it" <<'G'
doc =/ "a"
G
refuse "differ only in case" "digit beside DIGIT" <<G
include "$CORE"
doc   = 1*digit
digit = DIGIT
G

echo "== %d65.66 and *m =="
rm -f "$W/t"; gen <<'G'
doc  = 1*pair
pair = %d65.66
G
check OK   "ABAB" "two AB pairs"
check FAIL "ABA"  "a lone A"
rm -f "$W/t"; gen <<G
include "$CORE"
doc = *2DIGIT
G
check OK   "12"  "two digits"
check FAIL "123" "three digits"

echo "== sensitivity =="
rm -f "$W/t"; gen <<'G'
sensitivity string %i
doc = "hello" %s"World"
G
check OK   "HELLO World" "a bare literal ignores case"
check FAIL "hello world" "a %s literal does not"
rm -f "$W/t"; gen <<G
sensitivity rule-name %i
include "$CORE"
doc = 1*digit
G
check OK   "123" "digit finds DIGIT"
check FAIL "a"   "a letter"

echo "== <prose-val> =="
refuse_file tests/abnf/hole.hbnf "not written yet, in .unit.: <one of the units" "a hole the parser uses"
if grep -q "unused" "$W/err.txt"; then echo "  FAIL [an unused hole is reported]"; rc=1
else echo "  PASS [an unused hole is not reported]"; fi
if grep -q '^ *^$' "$W/err.txt"; then echo "  PASS [a caret under it]"
else echo "  FAIL [no caret]: $(cat "$W/err.txt")"; rc=1; fi
rm -f "$W/t"; gen_file tests/abnf/filled.hbnf
check OK   "123" "the hole filled by a later ="

echo "== core.hbnf: CRLF and WSP =="
rm -f "$W/t"; gen <<G
include "$CORE"
doc   = lines END
lines = 1*line
line  = A WSP A CRLF
A    = %x41
END  = %x2E
G
check OK   "$(printf 'A A\r\nA\tA\r\n.')" "two lines"
check FAIL "$(printf 'AA\r\n.')"          "no white space"
check FAIL "$(printf 'A A\n.')"            "LF without CR"

exit $rc
