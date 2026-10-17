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

# A dialect line prefixes every generated identifier (`ybnf_if`), so a rule
# named like a keyword of any target language needs no special case.
mkdir "$W/kw"
cat > "$W/kw/g.hbnf" <<G
dialect ybnf
whitespace none
doc = begin if match type fn end loop
begin = "b"
if = "i"
match = "m"
type = "t"
fn = "f"
end = "e"
loop = "l"
G
printf 'bimtfel' > "$W/kw/a1.txt"
printf 'bimtfe' > "$W/kw/r1.txt"; printf 'bimtfl' > "$W/kw/r2.txt"
ACCEPT=$(ls "$W"/kw/a*.txt)
REJECT=$(ls "$W"/kw/r*.txt)
suite "keyword rules" "$W/kw/g.hbnf" 2>/dev/null

# With no dialect line the prefix is `bnf_`, so the same grammar needs no
# special case there either; `prefix none` keeps the rules' own names.
mkdir "$W/kw2"
sed '1d' "$W/kw/g.hbnf" > "$W/kw2/g.hbnf"
suite "keyword rules, default prefix" "$W/kw2/g.hbnf" 2>/dev/null
(printf 'prefix none\n'; sed '1d' "$W/kw/g.hbnf") > "$W/kw2/h.hbnf"
suite "keyword rules, prefix none" "$W/kw2/h.hbnf" 2>/dev/null

# The exception with a phrase on a side: item - assign is an item that is not
# an assignment.  A is parsed; then B is tried on exactly the text A matched.
mkdir "$W/pe"
cat > "$W/pe/g.hbnf" <<G
whitespace ws
doc = x ";"
x = item - assign
item = name [ "=" arg ]
assign = name "=" arg
name = word
arg = word
ws = 1*wsc
wsc = %x20 / %x09
G
n=0
for v in 'a;' '  a  ;' 'abc ;' 'a ;'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/pe/a$n.txt"
done
n=0
for v in 'a = b;' 'a=b;' 'a  =   b ;' ';' 'a b;' '= b;'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/pe/r$n.txt"
done
ACCEPT=$(ls "$W"/pe/a*.txt)
REJECT=$(ls "$W"/pe/r*.txt)
suite "phrase exception" "$W/pe/g.hbnf" 2>/dev/null

# The same inside a list, so a rejected item must leave nothing behind.
mkdir "$W/pl"
sed 's/^doc = .*/doc = 1*( x ";" )/' "$W/pe/g.hbnf" > "$W/pl/g.hbnf"
n=0
for v in 'a;' 'a;b;c;' 'a ; b ;' 'a;b;'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/pl/a$n.txt"
done
n=0
for v in 'a;b=c;' 'a=b;c;' 'a;b;c=d;' ''; do
	n=$((n + 1)); printf '%s' "$v" > "$W/pl/r$n.txt"
done
ACCEPT=$(ls "$W"/pl/a*.txt)
REJECT=$(ls "$W"/pl/r*.txt)
suite "phrase exception in a list" "$W/pl/g.hbnf" 2>/dev/null

# An alias of a record used in a list entry, with no exception.
mkdir "$W/ar"
sed 's/^x = item - assign/x = item/; /^assign = /d' "$W/pl/g.hbnf" > "$W/ar/g.hbnf"
n=0
for v in 'a;' 'a;b;' 'a = b;' 'a=b;c;'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/ar/a$n.txt"
done
n=0
for v in ';' 'a' 'a;=;' ''; do
	n=$((n + 1)); printf '%s' "$v" > "$W/ar/r$n.txt"
done
ACCEPT=$(ls "$W"/ar/a*.txt)
REJECT=$(ls "$W"/ar/r*.txt)
suite "alias of a record in a list" "$W/ar/g.hbnf" 2>/dev/null

# An alias of a list rule: it stands for the list.
mkdir "$W/al"
cat > "$W/al/g.hbnf" <<G
whitespace ws
doc = x ";"
x = items
items = 1*item
item = name ","
name = word
ws = 1*wsc
wsc = %x20 / %x09
G
n=0
for v in 'a,;' 'a, b, c,;' ' a , b ,  ;'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/al/a$n.txt"
done
n=0
for v in ';' 'a;' 'a,' ',;' ''; do
	n=$((n + 1)); printf '%s' "$v" > "$W/al/r$n.txt"
done
ACCEPT=$(ls "$W"/al/a*.txt)
REJECT=$(ls "$W"/al/r*.txt)
suite "alias of a list rule" "$W/al/g.hbnf" 2>/dev/null

# Negation: ~x is one code point not in x, and *~x is a run of them.
mkdir "$W/ng"
cat > "$W/ng/g.hbnf" <<G
whitespace none
include "$(pwd)/grammars/common.hbnf"
doc = *( line LF )
line = comment / text
comment = "#" *~LF
text = 1*~( LF / "#" )
G
n=0
for v in '' 'a
' '#c
' 'a b
#c
d
' 'x y z
'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/ng/a$n.txt"
done
n=0
for v in 'a' 'a#b
' '
'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/ng/r$n.txt"
done
ACCEPT=$(ls "$W"/ng/a*.txt)
REJECT=$(ls "$W"/ng/r*.txt)
suite "negation, comments" "$W/ng/g.hbnf" 2>/dev/null

mkdir "$W/ns"
cat > "$W/ns/g.hbnf" <<G
whitespace none
include "$(pwd)/grammars/common.hbnf"
doc = str
str = DQUOTE *( esc / plain ) DQUOTE
esc = %x5C %x00-10FFFF
plain = ~( DQUOTE / %x5C )
G
n=0
for v in '""' '"abc"' '"a\"b"' '"a\\"' '"é"'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/ns/a$n.txt"
done
n=0
for v in '"abc' '"a"b"' '"\"' 'abc' ''; do
	n=$((n + 1)); printf '%s' "$v" > "$W/ns/r$n.txt"
done
ACCEPT=$(ls "$W"/ns/a*.txt)
REJECT=$(ls "$W"/ns/r*.txt)
suite "negation, strings" "$W/ns/g.hbnf" 2>/dev/null

mkdir "$W/nu"
cat > "$W/nu/g.hbnf" <<G
whitespace none
doc = *~"é" "é"
G
n=0
for v in 'é' 'abcé' 'aé'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/nu/a$n.txt"
done
n=0
for v in 'abc' '' 'ééx'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/nu/r$n.txt"
done
ACCEPT=$(ls "$W"/nu/a*.txt)
REJECT=$(ls "$W"/nu/r*.txt)
suite "negation, a non-ASCII complement" "$W/nu/g.hbnf" 2>/dev/null

# Enum values: `"icmp"@1`, a literal with a number of its own.  The numbers
# are checked in C by tests/enumval.sh; here all four backends must build the
# sparse enum and read its names.
mkdir "$W/ev"
cp tests/enumval/proto.hbnf "$W/ev/g.hbnf"
n=0
for v in 'udp 1' 'icmp 22' 'tcp 3' 'sctp 4' 'other 5' 'ipv6-icmp 6'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/ev/a$n.txt"
done
n=0
for v in 'UDP 1' 'ip 1' 'tcp6 1' '' 'icmp tcp'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/ev/r$n.txt"
done
ACCEPT=$(ls "$W"/ev/a*.txt)
REJECT=$(ls "$W"/ev/r*.txt)
suite "enum values" "$W/ev/g.hbnf" 2>/dev/null

# Tokens everywhere: a rule that is only text, in a file that skips no
# whitespace, is one token whose value is its text, whatever it is made of.
mkdir "$W/tk"
cat > "$W/tk/g.hbnf" <<G
whitespace none
include "$(pwd)/grammars/common.hbnf"
doc = scheme ":" path [ "?" query ]
scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
path = *( "/" segment )
segment = *pchar
pchar = ALPHA / DIGIT / "-" / "." / "_" / "~"
query = 1*( pchar / "=" / "&" )
G
n=0
for v in 'a:' 'http:/a/b' 'x1:/' 'a+b-c.d:/p/q?k=v&m=1' 'a:?x'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/tk/a$n.txt"
done
n=0
for v in '1a:' 'a' 'a:/b c' 'a:/b?' ':/x'; do
	n=$((n + 1)); printf '%s' "$v" > "$W/tk/r$n.txt"
done
ACCEPT=$(ls "$W"/tk/a*.txt)
REJECT=$(ls "$W"/tk/r*.txt)
suite "text rules are tokens" "$W/tk/g.hbnf" 2>/dev/null

exit $rc
