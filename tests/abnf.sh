#!/bin/sh
# RFC 5234 forms the reader takes (RFCPLAN.md step 1): `/` between single
# characters, `=/`, `%d13.10`, `*m`, continuation by indentation, newlines
# inside ( ), `sensitivity`, <prose-val>, and common.hbnf.  Each grammar is
# generated as C, compiled, and run on inputs it must accept or reject;
# the schemas it must refuse are checked for the reason given.
#   HBNF=/path/to/hbnf sh tests/abnf.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
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

warns() { # $1=text the warning must hold, $2=label; grammar on stdin: it generates, and says so
	cat > "$W/warn.hbnf"
	if ! "$CLI" "$W/warn.hbnf" --backend=c > /dev/null 2> "$W/err.txt"; then
		echo "  FAIL [$2]: refused: $(head -1 "$W/err.txt")"; rc=1; return
	fi
	if grep -q -- "$1" "$W/err.txt"; then
		echo "  PASS [$2]: compiled, with the warning"
	else
		echo "  FAIL [$2]: compiled, but no warning with: $1"; rc=1
	fi
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

CORE="$HERE/grammars/common.hbnf"

echo "== \`/\` between single characters =="
rm -f "$W/t"; gen <<G
include "$CORE"
doc  = 1*item
item = DIGIT / ALPHA
G
check OK   "a1B" "letters and digits"
check FAIL "-"   "neither"
warns "first match wins" "/ between phrases that match the same text" <<'G'
doc = x / y
x = "a" "b"
y = 1*( "a" / "b" )
G
rm -f "$W/t"; gen <<'G' 2>/dev/null
doc = x / y
x = "a" "b"
y = 1*( "a" / "b" )
G
check OK   "ab"    "x is taken first: it is followed by the end"
check OK   "abab"  "y when x is not followed by what can follow doc"
check FAIL "abc"   "neither"

echo "== \`/\` between phrases: the reader finds the order that works (step 5) =="
rm -f "$W/t"; gen <<'G'
doc = "a" "b" / "c" "d"
G
check OK   "ab"  "first alternative"
check OK   "cd"  "second alternative"
check FAIL "ad"  "neither"
check FAIL "a"   "a prefix of the first"
rm -f "$W/t"; gen <<'G'
doc = [ "x" ] / "y"
G
check OK   "y"   "the empty alternative, written first, is tried last"
check OK   "x"   "the optional one"
check OK   ""    "nothing at all"
check FAIL "z"   "neither"
rm -f "$W/t"; gen <<'G'
doc = *( "a" "b" / "c" )
G
check OK   "abcab" "a union inside a repeated group"
check FAIL "abb"   "a leftover"
rm -f "$W/t"; gen <<'G'
doc = "/" "/" "x" / "/" "y"
G
check OK   "//x" "two code points tell them apart"
check OK   "/y"  "the other alternative"
check FAIL "/x"  "neither"
check FAIL "//y" "neither, the other way"
rm -f "$W/t"; gen <<G
include "$CORE"
doc = oct
oct = DIGIT / %x31-39 DIGIT / "1" 2DIGIT
G
check OK   "7"   "a character rule takes the longest alternative: one digit"
check OK   "42"  "two digits"
check OK   "199" "three digits, in the RFC's own order"
check FAIL "a"   "not a digit"
echo "== <name> rules, as Backus and Naur write them: one rule, whatever the operator =="
for op in "::=" ":=" ":" "="; do
	rm -f "$W/t"; gen <<G 2>/dev/null
<number> $op <digit> <digit>
<digit> $op "0" | "1"
G
	check OK   "01"  "\`$op\`: rules named <number> and <digit>"
	check FAIL "02"  "\`$op\`: 2 is no digit"
done
rm -f "$W/t"; gen <<'G'
<unsigned integer> = <digit> | <unsigned integer> <digit>
<digit> = "0" | "1"
G
check OK   "1011" "a name with a space, and left recursion through it"
check FAIL "12"   "2 is no digit"
rm -f "$W/t"; gen <<'G'
doc = <d> d
d = "y"
G
check OK   "yy"   "<d> is the rule d"
rm -f "$W/t"; gen <<'G'
doc = <my scanner> "x"
<my scanner> = %scan { size_t i = pos; while (i < len && s[i] == 'a') i++; return i - pos; }
G
check OK   "aax"  "%scan under a <name>"
check FAIL "x"    "the scanner needs an a"
printf '"a" | "b"\n' > "$W/body.txt"
rm -f "$W/t"; gen <<G
doc = <letter> "!"
<letter> = %grammar "$W/body.txt"
G
check OK   "a!"   "%grammar reads the body of a rule from a file"
check FAIL "c!"   "c is not in the file's body"
refuse "no such file" "%grammar with no such file" <<'G'
doc = x
x = %grammar "/no/such/file.hbnf"
G
refuse "a bare number" "a terminal written bare, as BNF writes it" <<'G'
<digit> ::= 0 | 1
G
refuse "writes it in quotes" "a bare name that no rule defines" <<'G'
doc = foo
G
refuse "names a rule" "a <...> that no rule defines" <<'G'
doc = <not written yet> "x"
G

echo "== the \`dialect\` line: ISO 14977 EBNF and RFC 5234 ABNF =="
rm -f "$W/t"; gen <<'G'
dialect ebnf
(* a number: three digits, a point, then as many digits as you like *)
doc = num , "!" ;
num = 3 * digit
    , [ '.' ]
    , { digit } ;
digit = '0' | '1' ;
G
check OK   "011!"     "n * x is exactly n; a rule may run over several lines"
check OK   "011.11!"  "[ x ] and { x }, joined by commas"
check OK   "0111!"    "{ x } takes more digits"
check FAIL "01!"      "fewer than three"
refuse "EBNF's way of writing exactly 3" "a spaced n * x in the default notation" <<'G'
digit = "0" | "1"
doc = 3 * digit
G
refuse "not written yet" "a special sequence is a rule not written yet" <<'G'
dialect ebnf
doc = ? any character ? , "x" ;
G

rm -f "$W/t"; gen <<'G'
dialect abnf
doc = 2DIGIT "\" 1*ALPHA
DIGIT = %x30-39
ALPHA = %x41-5A / %x61-7A
G
check OK   '12\ab' "dialect abnf: nothing is skipped, and \"\\\" is a backslash"
check FAIL '12 \ab' "a space is not skipped"
rm -f "$W/t"; gen <<'G'
dialect hbnf
doc = "a" "b"
G
check OK   "a b"  "dialect hbnf is the default notation"
refuse "takes .bnf., .ebnf." "a dialect that is not one" <<'G'
dialect pascal
doc = "a"
G

echo "== the exception a - b: a token that is not one of a few =="
rm -f "$W/t"; gen <<'G'
whitespace none
doc = word-ok "." tail
word-ok = word-any - reserved
word-any = lower *( lower / digit / "-" )
lower = %x61-7A
digit = %x30-39
reserved = ( "if" / "then" ) / "fi" / 2( "x" / "y" )
tail = word-any
G
check OK   "abc.x"    "a word that is not reserved"
check OK   "iff.d"    "a word that begins with one is not that word"
check OK   "if-1.a"   "a longer word that begins with one"
check FAIL "if.a"     "if is reserved"
check FAIL "then.b"   "so is then"
check FAIL "xy.b"     "a group repeated is a token too"
check OK   "xyz.b"    "but not a longer word"
refuse "cannot be one token" "an operand with a built-in scanner inside" <<'G'
whitespace none
doc = word-ok "."
word-ok = word-any - phrase
word-any = 1*lower
lower = %x61-7A
phrase = word "!"
G

echo "== YBNF, yacc's grammar language: %token, %start, %%, and | as the union =="
rm -f "$W/t"; gen <<'G'
dialect ybnf
%token WORD
%start list
%%
list : list WORD
     | WORD
     ;
WORD = 1*ALPHA
ALPHA = %x41-5A / %x61-7A
G
check OK   "ab cd ef" "a list of tokens, left recursive, the standard's way"
check FAIL "ab 12"   "12 is no token"
rm -f "$W/t"; gen <<'G'
dialect ybnf
%start doc
%%
doc : 'x' 'y'
    | 'x'
    ;
G
check OK   "xy" "| is the union: the longer alternative is found, though written second"
check OK   "x"  "and the shorter one"
refuse 'AND_IF = "&&"' "a %token with no rule says how to write it, with the standard's spelling" <<'G'
dialect ybnf
%token AND_IF
/*      '&&'      */
%%
list : list AND_IF list
     | 'x'
     ;
G
refuse "class of text" "a %token with no spelling is a class of text" <<'G'
dialect ybnf
%token WORD
%%
list : WORD
     ;
G

echo "== a repetition ABNF would give back (step 5) =="
rm -f "$W/t"; gen <<G
include "$CORE"
doc = [ *1( h ":" ) h ] "::" "z"
h = 1*4DIGIT
G
check OK   "1::z"     "the RFC's own form: the group is not taken from the :: "
check OK   "1:2::z"   "one group, then ::"
check OK   "::z"      "nothing before ::"
check FAIL "1:2:3::z" "more groups than *1 allows"
refuse "matched greedily" "a repetition that takes what follows needed" <<'G'
whitespace none
doc = *( "a" ) "a"
G
rm -f "$W/t"; gen <<'G'
whitespace none
doc = *( "a" ) "b"
G
check OK   "aaab" "a repetition that cannot take what follows"
check FAIL "aaa"  "nothing after the repetitions"
warns "first match wins" "an alternative that can match nothing, and the follow set can begin another" <<'G'
doc = x "a"
x = "a" / [ "b" ]
G
rm -f "$W/t"; gen <<'G'
doc = "a" "b" "c" / "a" "b" "d"
G
check OK   "abc" "a shared prefix of any length"
check OK   "abd" "the other alternative"
check FAIL "ab"  "neither"
check FAIL "abe" "neither, after the prefix"
rm -f "$W/t"; gen <<'G'
doc = "a" / "a" "b"
G
check OK   "a"   "the shorter alternative, written first"
check OK   "ab"  "the longer: the reader tries it first"
check FAIL "abb" "a leftover"
rm -f "$W/t"; gen <<'G'
doc = x / y
x = "a" "b" "c"
y = "a" "b" "d"
G
check OK   "abc" "alternatives that are rules, with a shared prefix"
check OK   "abd" "the other"
rm -f "$W/t"; gen <<G
include "$CORE"
doc = a / b
a = 1*DIGIT "."
b = 1*DIGIT ":"
G
check OK   "123." "told apart after any number of digits"
check OK   "123:" "the other"
check FAIL "123"  "neither"

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

echo "== ',' in a rule of words: the literal \",\" =="
rm -f "$W/t"; gen <<'G'
hosts    = '{' hostlist '}'
hostlist = hostlist ',' host | hostlist host | host
host     = word
G
check OK   "{ a, b c }" "commas that may be left out"
check FAIL "{ a, }"     "a trailing comma"
rm -f "$W/t"; gen <<'G'
r = word %x30-39
G
check OK   "ab 7" "a range in a rule of words is a rule of its own, which the reader writes"
check FAIL "ab"   "the range needs a digit"

echo "== groups, optionals and repetition inside a sequence (step 2) =="
rm -f "$W/t"; gen <<'G'
hosts = '{' host *( ',' host ) '}'
host  = word [ "port" int ] ( "tcp" | "udp" )
G
check OK   "{ a tcp, b port 22 udp }" "RFC-style list, an optional, an alternation"
check FAIL "{ a tcp, }"               "a trailing comma"
check FAIL "{ a port udp }"           "port without its number"
check FAIL "{ a }"                    "neither tcp nor udp"

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

echo "== copy-paste syntax: the other notations' operators (step 7a) =="
# A grammar lifted out of an RFC, a POSIX spec or a yacc file reads as
# written.  Each spelling has to produce the same parser.
for op in "=" "::=" ":=" ":"; do
	rm -f "$W/t"; gen <<G
include "$CORE"
doc  $op sum
sum  $op num "+" num
num  $op 1*DIGIT
G
	check OK   "1+2" "\`$op\` as the assignment operator"
	check FAIL "1-2" "\`$op\`: a wrong operator is still refused"
done

# A yacc production, pasted: `:`, `|`, and the `;` terminator on its own
# line under the last alternative.  The `;` works because it starts an ABNF
# comment, so the rule has already ended at the newline.
rm -f "$W/t"; gen <<G
include "$CORE"
doc  : expr
expr : term "+" term
     | term
     ;
term : 1*DIGIT
G
check OK   "1+2" "a pasted yacc production: sum"
check OK   "7"   "a pasted yacc production: bare term"
check FAIL "+"   "a pasted yacc production still refuses nonsense"

echo "== copy-paste syntax: three comment styles (step 7a) =="
rm -f "$W/t"; gen <<G
include "$CORE"
/* a C and yacc comment, on its own line */
doc  = sum                  ; an ABNF comment
sum  = num "+" num          /* a trailing C comment */
num  = 1*DIGIT              (* a trailing Wirth comment *)
/* a C comment
   spanning lines, read as white space */
G
check OK   "1+2" "all three comment styles in one schema"
check FAIL "1"   "and the rule still means what it said"

# `(*` opens a Wirth comment only when a blank follows, so a group holding a
# repetition is still a group.
rm -f "$W/t"; gen <<G
include "$CORE"
doc = 1*(*LETTERS)
LETTERS = ALPHA
G
check OK "abc" "\`(*LETTERS)\` is a group, not a comment"

refuse 'comment is never closed' "an unclosed /* is named" <<G
include "$CORE"
doc = "a" /* and then nothing
G
refuse 'comment is never closed' "an unclosed (* is named" <<G
include "$CORE"
doc = "a" (* and then nothing
G

echo "== the warning channel, and 7a's `:` notice (step 12) =="
# A warning does not stop generation; --werror makes it fail at the end, so
# every warning is reported first.  7a left this notice unbuilt for want of
# a channel: a yacc `:` grammar compiles, and yacc's `|` is unordered while
# hbnf's is first-match, so it must say so -- once per file.
rm -f "$W/t"
cat > "$W/y.hbnf" <<Y
language C
include "$CORE"
doc  : sum
sum  : num "+" num2
num  : 1*DIGIT
num2 : 1*DIGIT
Y
if "$CLI" "$W/y.hbnf" --backend=c > /dev/null 2> "$W/err.txt"; then
	n=$(grep -c "warning:" "$W/err.txt")
	if [ "$n" = 1 ] && grep -q "ordered" "$W/err.txt"; then
		echo "  PASS [a \`:\` schema warns once and still generates]"
	else
		echo "  FAIL [a \`:\` schema warns once and still generates]: $n warning(s)"; rc=1
	fi
else
	echo "  FAIL [a \`:\` schema warns once and still generates]: refused"; rc=1
fi
if "$CLI" "$W/y.hbnf" --backend=c --werror > /dev/null 2> "$W/err.txt"; then
	echo "  FAIL [--werror turns it into a failure]: accepted"; rc=1
else
	if grep -q -- "--werror" "$W/err.txt"; then
		echo "  PASS [--werror turns it into a failure]"
	else
		echo "  FAIL [--werror turns it into a failure]: $(head -1 "$W/err.txt")"; rc=1
	fi
fi
sed 's/ : / = /' "$W/y.hbnf" > "$W/e.hbnf"
if "$CLI" "$W/e.hbnf" --backend=c --werror > /dev/null 2> "$W/err.txt" \
   && [ ! -s "$W/err.txt" ]; then
	echo "  PASS [an \`=\` schema is silent under --werror]"
else
	echo "  FAIL [an \`=\` schema is silent under --werror]: $(head -1 "$W/err.txt")"; rc=1
fi
# the shadowing report moved onto the same channel
cat > "$W/sh.hbnf" <<Y
language C
include "$CORE"
doc = a
a = "x" | "x" "y"
Y
if "$CLI" "$W/sh.hbnf" --backend=c > /dev/null 2> "$W/err.txt"; then
	echo "  FAIL [a shadowed alternative warns and fails]: accepted"; rc=1
elif grep -q "warning:.*can never match" "$W/err.txt"; then
	echo "  PASS [a shadowed alternative warns and fails]"
else
	echo "  FAIL [a shadowed alternative warns and fails]: $(head -1 "$W/err.txt")"; rc=1
fi

echo "== a repeated bare literal is refused, not crashed on (step 12) =="
# `doc = *"a"` is a list whose every entry holds nothing.  C and Zig used to
# raise CONSTRAINT_ERROR on a discriminant check; Rust and Ada emitted a
# parser referencing an entry type they never declared.  One check in
# HBNF_Compilable now refuses it for all four, and names both spellings that
# work.
for shape in '*"a"' '( *"a" )' '1*"a"' '"k" *"a"' '3*5"a"'; do
	printf 'language C\ndoc = %s\n' "$shape" > "$W/rl.hbnf"
	for b in c rust zig ada; do
		if "$CLI" "$W/rl.hbnf" --backend=$b > /dev/null 2> "$W/err.txt"; then
			echo "  FAIL [doc = $shape refused by $b]: accepted"; rc=1
		elif grep -q "repeated literal" "$W/err.txt"; then
			:
		else
			echo "  FAIL [doc = $shape refused by $b]: $(head -1 "$W/err.txt")"; rc=1
		fi
	done
	echo "  PASS [doc = $shape: all four backends refuse it, with the reason]"
done
# and the spellings the message names do work
for shape in '*( "a" )' '*%x41' '"k" *word'; do
	printf 'language C\ndoc = %s\n' "$shape" > "$W/rl.hbnf"
	ok=1
	for b in c rust zig ada; do
		"$CLI" "$W/rl.hbnf" --backend=$b > /dev/null 2> "$W/err.txt" || ok=0
	done
	if [ "$ok" = 1 ]; then
		echo "  PASS [doc = $shape still compiles everywhere]"
	else
		echo "  FAIL [doc = $shape still compiles everywhere]: $(head -1 "$W/err.txt")"; rc=1
	fi
done

echo "== a run that may be empty (*X) in a phrase rule =="
# `*DIGIT` before another element used to fail the rule when no digit was
# there: its hidden scanner rule demanded at least one character.  The rule
# has to be a phrase rule (the literal `go` makes it one) to be lifted.
rm -f "$W/t"; gen <<G
include "$CORE"
whitespace SP
doc = *DIGIT "go"
G
check OK   "go"   "no digit at all"
check OK   "42go" "digits first"
check FAIL "42"   "but the word is still required"

echo "== recursive tree types (RFCPLAN step 9) =="
# All four backends emit the field that breaks the cycle as a pointer (step
# 9b), so the grammar generates; C is compiled and run here, the others by
# tests/recursive.sh.  Rust used to emit code rustc rejected (E0072) and Zig
# code that failed the moment a size was forced (step 9a).
rm -f "$W/t"; gen_file tests/abnf/recursive.hbnf
check OK "(1)" "a recursive tree type parses, in C"
check FAIL "1)" "and an unbalanced one is rejected"
for b in ada rust zig; do
	if "$CLI" tests/abnf/recursive.hbnf --backend=$b > /dev/null 2> "$W/err.txt"; then
		echo "  PASS [the $b backend emits it now]"
	else
		echo "  FAIL [the $b backend emits it now]: $(head -1 "$W/err.txt")"; rc=1
	fi
done
# A failed branch's pointer must not read as set in the branch that matched:
# `(5)` matches `'(' int ')'`, after `'(' x ')'` set the back-edge field and
# failed, and the reset frees what the failed branch set.
if "$CLI" tests/abnf/recursive-direct.hbnf --backend=c > "$W/rd.c" 2> "$W/err.txt"; then
	RDROOT=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/rd.c")
	cp "$W/rd.c" "$W/rdm.c"
	cat >> "$W/rdm.c" <<EOC
int main(int argc, char **argv) {
    $RDROOT out; char err[512]; size_t l = 0, c = 0;
    if (argc < 2 || !parse_text(argv[1], &out, err, sizeof err, &l, &c)) return 1;
    printf("%s\n", out.x ? "set" : "null"); return 0;
}
EOC
	if gcc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$W/rdm.c" -o "$W/rd"; then
		for want in "(5):null" "((5)):set"; do
			in=${want%%:*}; exp=${want##*:}
			got=$("$W/rd" "$in" 2>&1)
			if [ "$got" = "$exp" ]; then
				echo "  PASS [a failed branch leaves the back edge empty: $in -> $got]"
			else
				echo "  FAIL [a failed branch leaves the back edge empty: $in -> '$got', wanted $exp]"; rc=1
			fi
		done
	else
		echo "  FAIL [recursive-direct does not compile in C]"; rc=1
	fi
else
	echo "  FAIL [recursive-direct generates in C]: $(head -1 "$W/err.txt")"; rc=1
fi
# The same for an ordinary field: a failed branch is freed and then zeroed, so
# the field it set does not read as set in the branch that matched.  `a` is set
# by the first branch, which then fails on `)`; the second sets `b` only.
cat > "$W/stale.hbnf" <<EOG
language C
include "$CORE"

t = a ')' | b
a = word
b = word
EOG
if "$CLI" "$W/stale.hbnf" --backend=c > "$W/st.c" 2> "$W/err.txt"; then
	STROOT=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/st.c")
	cp "$W/st.c" "$W/stm.c"
	cat >> "$W/stm.c" <<EOC
int main(int argc, char **argv) {
    $STROOT out; char err[512]; size_t l = 0, c = 0;
    if (argc < 2 || !parse_text(argv[1], &out, err, sizeof err, &l, &c)) return 1;
    printf("a=%s b=%s\n", out.a ? "set" : "null", out.b ? "set" : "null"); return 0;
}
EOC
	if gcc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$W/stm.c" -o "$W/st"; then
		for want in "foo:a=null b=set" "foo):a=set b=null"; do
			in=${want%%:*}; exp=${want#*:}
			got=$("$W/st" "$in" 2>&1)
			if [ "$got" = "$exp" ]; then
				echo "  PASS [a failed branch's field is cleared: $in -> $got]"
			else
				echo "  FAIL [a failed branch's field is cleared: $in -> '$got', wanted '$exp']"; rc=1
			fi
		done
	else
		echo "  FAIL [the stale-field grammar does not compile in C]"; rc=1
	fi
else
	echo "  FAIL [the stale-field grammar generates in C]: $(head -1 "$W/err.txt")"; rc=1
fi
# A cycle laundered through a list is *not* a cycle: a list field holds the
# list's head, which is two pointers.  It used to be emitted as one of the
# list's nodes by value, which is the C that would not compile (step 9a).
if "$CLI" tests/abnf/recursive-via-list.hbnf --backend=c > "$W/rl.c" 2>"$W/err.txt"; then
	if gcc -c -w -o /dev/null -Itests/bsdinc -xc "$W/rl.c" 2>"$W/cc.txt"; then
		echo "  PASS [a list breaks the cycle, and the C compiles]"
	else
		echo "  FAIL [a list breaks the cycle, and the C compiles]: $(grep -m1 error "$W/cc.txt")"; rc=1
	fi
else
	echo "  FAIL [a list breaks the cycle, and the C compiles]: $(head -1 "$W/err.txt")"; rc=1
fi
for b in ada rust zig; do
	if "$CLI" tests/abnf/recursive-via-list.hbnf --backend=$b > /dev/null 2>"$W/err.txt"; then
		echo "  PASS [the $b backend takes it too]"
	else
		echo "  FAIL [the $b backend takes it too]: $(head -1 "$W/err.txt")"; rc=1
	fi
done

echo "== common.hbnf: CRLF and WSP =="
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
