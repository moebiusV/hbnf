#!/bin/sh
# The obconf configuration-file grammar (hbnf_schema.hbnf), generated in every
# backend and run over the conformance files in tests/accept and tests/reject:
# each accept file must parse and each reject file must not.  This is the
# grammar the hand-written reader HBNF_Config (retired in 9c) was checked
# against.
#
# The same four-backend harness also runs the repetition grammars at the end:
# a repeated rule that can match nothing must terminate (RFCPLAN decision 9),
# which the interpreter HBNF_Match (retired in 9c) used to be the only test of.
#
# One reject file is left out, and says why: 005-decimal-overflow.conf is `x
# 1e40`, refused because the hand-written reader's fixed-point Decimal cannot
# hold it.  A grammar has no value range, so the generated parser reads `1e40`
# as a word and accepts it; that is the Decimal type, not the notation.
#
# SCHEMA_BACKENDS says which backends are gated (default: all four).
#   HBNF=/path/to/hbnf sh tests/schema.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${SCHEMA_BACKENDS:-c ada rust zig}"
want() { case " $BACKENDS " in *" $1 "*) return 0 ;; esac; return 1; }

. tests/suite.sh

ACCEPT=$(ls tests/accept/*.conf)
REJECT=$(ls tests/reject/*.conf | grep -v 005-decimal-overflow)
suite schema hbnf_schema.hbnf

# A repeated rule that can match nothing: `empty` matches `a` or nothing.  Each
# shape must accept the empty text, `a` and `a a`, refuse `aa` (one bareword,
# not the keyword), and above all END: it used to loop forever on `aa`.  The
# grammars name `word`, so "a" is a keyword (without words it is the byte).
mkdir "$W/rep"
printf '' > "$W/rep/empty.txt"
printf 'a' > "$W/rep/a.txt"
printf 'a a' > "$W/rep/a_a.txt"
printf 'aa' > "$W/rep/aa.txt"
ACCEPT="$W/rep/empty.txt $W/rep/a.txt $W/rep/a_a.txt"
REJECT="$W/rep/aa.txt"
n=0
for body in 'config = *empty' 'config = 1*empty' 'config = *( [ "a" ] )'; do
	n=$((n + 1))
	{ printf 'language C\n%s\n' "$body"; printf 'empty = [ "a" ]\nw = word\n'; } > "$W/rep/g$n.hbnf"
	suite "repeat $n" "$W/rep/g$n.hbnf"
done

# A scanner written once for each backend (`name = Rust { ... }`): the same
# grammar means the same in all four.
mkdir "$W/term"
cat > "$W/term/g.hbnf" <<'G'
language C
doc = digits ( "," | ";" ) digits
digits = C { size_t i = pos; while (i < len && s[i] >= '0' && s[i] <= '9') i++; return i - pos; }
digits = Rust { let mut i = pos; while i < len && s[i].is_ascii_digit() { i += 1; } i - pos }
digits = Zig { var i = pos; while (i < len and s[i] >= '0' and s[i] <= '9') i += 1; return i - pos; }
digits = Ada {
      I : Natural := Pos;
   begin
      while I <= Len and then S (I) in '0' .. '9' loop
         I := I + 1;
      end loop;
      return I - Pos;
G
printf '%s\n' '}' >> "$W/term/g.hbnf"
printf '12,345' > "$W/term/a1.txt"
printf '7;8' > "$W/term/a2.txt"
printf '12,' > "$W/term/r1.txt"
printf '1;;2' > "$W/term/r2.txt"
printf 'a,1' > "$W/term/r3.txt"
ACCEPT="$W/term/a1.txt $W/term/a2.txt"
REJECT="$W/term/r1.txt $W/term/r2.txt $W/term/r3.txt"
suite "terminal scanners" "$W/term/g.hbnf"

# First match wins (RFC 3986 section 3.2.2, `host`): an address is a name too,
# so the union needs backtracking; hbnf takes the first alternative that is
# followed by something that can follow the choice, here `:` or the end.
mkdir "$W/fm"
cat > "$W/fm/g.hbnf" <<G
whitespace none
include "$(pwd)/grammars/common.hbnf"
doc = host [ ":" 1*DIGIT ]
host = addr / name
addr = octet "." octet "." octet "." octet
octet = 1*3DIGIT
name = label *( "." label )
label = 1*( ALPHA / DIGIT )
G
n=0
for v in 1.2.3.4 1.2.3.4.5 a.b example 1.2.3.4:80 1.2.3.4.5:80; do
	n=$((n + 1)); printf '%s' "$v" > "$W/fm/a$n.txt"
done
n=0
for v in 1.2.3.4: :80 1.2.3.4..5 ""; do
	n=$((n + 1)); printf '%s' "$v" > "$W/fm/r$n.txt"
done
ACCEPT=$(ls "$W"/fm/a*.txt)
REJECT=$(ls "$W"/fm/r*.txt)
suite "first match wins" "$W/fm/g.hbnf" 2>/dev/null

# An exception, a - b: the same in all four backends.
mkdir "$W/ex"
cat > "$W/ex/g.hbnf" <<G
whitespace none
doc = word-ok "." tail
word-ok = word-any - reserved
word-any = lower *( lower / digit / "-" )
lower = %x61-7A
digit = %x30-39
reserved = ( "if" / "then" ) / "fi" / 2( "x" / "y" )
tail = word-any
G
printf 'abc.x' > "$W/ex/a1.txt"; printf 'iff.d' > "$W/ex/a2.txt"; printf 'if-1.a' > "$W/ex/a3.txt"; printf 'xyz.b' > "$W/ex/a4.txt"
printf 'if.a' > "$W/ex/r1.txt"; printf 'then.b' > "$W/ex/r2.txt"; printf 'fi.c' > "$W/ex/r3.txt"; printf '.a' > "$W/ex/r4.txt"; printf 'xy.b' > "$W/ex/r5.txt"
ACCEPT=$(ls "$W"/ex/a*.txt)
REJECT=$(ls "$W"/ex/r*.txt)
suite "exception" "$W/ex/g.hbnf" 2>/dev/null

exit $rc
