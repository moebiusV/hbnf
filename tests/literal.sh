#!/bin/sh
# The read-time spellings of hbnf's own notation (tests/literal/tokens.hbnf): i"..." and s"..." for the case of a
# string, r"..." for a regular expression read into the rule of characters it stands for, and C numbers for code
# points (0x41, 65, 0b1000001, 0x41..0x5A).  Each line of tests/literal/cases.txt is a verdict (ok or bad) and an
# input; every backend installed must give it (tree-sitter only has to generate).  Then every refusal, with its
# message, and the old `%x` and `%i` forms, which hbnf's own notation refuses and `dialect abnf` reads.
#   HBNF=/path/to/hbnf sh tests/literal.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
n=0; fail=0
mkdir -p "$W/cases"; i=0
while IFS="$(printf '\t')" read -r want input; do
	i=$((i + 1)); printf '%s' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
done < tests/literal/cases.txt
nc=$i
verdicts() {   # BACKEND OUTPUT: every case has the verdict written for it
	k=1
	while [ $k -le $nc ]; do
		want=$(cat "$W/cases/c$k.want")
		got=$(grep -F "c$k.txt" "$2" | head -1 | cut -d' ' -f1)
		[ -n "$got" ] || got=none
		[ "$got" = "$want" ] || { echo "literal: FAIL ($1: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
		k=$((k + 1))
	done
	n=$((n + 1))
}
G=tests/literal/tokens.hbnf
"$CLI" $G --backend=c > "$W/p.c" 2> "$W/err" || { echo "literal: FAIL (does not generate for C: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/pm.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/pm.c" -o "$W/pcheck" 2> "$W/cc.err" || { echo "literal: FAIL (C: $(head -c 300 "$W/cc.err"))"; exit 1; }
"$W/pcheck" "$W"/cases/c*.txt > "$W/p.out" 2>&1; verdicts c "$W/p.out"
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" $G --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "literal: FAIL (does not generate for Rust: $(head -c 300 "$d/err"))"; fail=1; }
	sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
	if (cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts rust "$d/out"
	else echo "literal: FAIL (Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" $G --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "literal: FAIL (does not generate for Zig: $(head -c 300 "$d/err"))"; fail=1; }
	: > "$d/files.txt"; k=1
	while [ $k -le $nc ]; do
		cp "$W/cases/c$k.txt" "$d/f$k.dat"
		printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
		k=$((k + 1))
	done
	sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
		"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out"
	else echo "literal: FAIL (Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" $G --backend=ada --package=Lt > "$d/all.ada" 2> "$d/err" || { echo "literal: FAIL (does not generate for Ada: $(head -c 300 "$d/err"))"; fail=1; }
	root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
	sed "s/MODULE/Lt/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
	if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts ada "$d/out"
	else echo "literal: FAIL (Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
fi
"$CLI" $G --backend=tree-sitter > "$W/ts.js" 2> "$W/err" && [ -s "$W/ts.js" ] \
	|| { echo "literal: FAIL (does not generate for tree-sitter: $(head -c 300 "$W/err"))"; fail=1; }

# A grammar is written, generated for C, and must be refused with a message that has the words; or (accept) read.
refuse() {   # TITLE 'GRAMMAR TEXT' 'WORDS IN THE MESSAGE'
	printf '%s\n' "$2" > "$W/r.hbnf"
	if "$CLI" "$W/r.hbnf" --backend=c > /dev/null 2> "$W/err"; then
		echo "literal: FAIL ($1 is accepted)"; fail=1
	elif ! grep -qF -- "$3" "$W/err"; then
		echo "literal: FAIL ($1: the message lacks \`$3\`: $(head -c 400 "$W/err"))"; fail=1
	fi
	n=$((n + 1))
}
accept() {   # TITLE 'GRAMMAR TEXT'
	printf '%s\n' "$2" > "$W/r.hbnf"
	"$CLI" "$W/r.hbnf" --backend=c > /dev/null 2> "$W/err" \
		|| { echo "literal: FAIL ($1 is refused: $(head -c 300 "$W/err"))"; fail=1; }
	n=$((n + 1))
}
H='prefix none
whitespace none'
refuse "a lazy repetition" "$H
a = r\"a*?b\"" "lazy"
refuse "a possessive repetition" "$H
a = r\"a*+b\"" "possessive"
refuse "a back-reference" "$H
a = r\"(a)\\1\"" "back-reference"
refuse "a lookahead" "$H
a = r\"a(?=b)\"" "write \`&x\`"
refuse "a negative lookahead" "$H
a = r\"a(?!b)\"" "write \`!x\`"
refuse "a lookbehind" "$H
a = r\"(?<=a)b\"" "looks behind"
refuse "an anchor ^" "$H
a = r\"^a\"" "anchor"
refuse "an anchor \$" "$H
a = r\"a\$\"" "anchor"
refuse "an anchor \\b" "$H
a = r\"\\ba\"" "anchor"
refuse "an inline flag" "$H
a = r\"(?i)a\"" "the case flag is the prefix"
refuse "a named group" "$H
a = r\"(?P<n>a)\"" "named group"
refuse "a brace that is no count" "$H
a = r\"a{x}\"" "not a count"
refuse "an empty brace" "$H
a = r\"a{}\"" "not a count"
refuse "a nothing to repeat" "$H
a = r\"*a\"" "nothing to repeat"
refuse "an unclosed group" "$H
a = r\"(a\"" "never closed"
refuse "an unclosed class" "$H
a = r\"[a\"" "never closed"
refuse "an empty regular expression" "$H
a = r\"\"" "empty"
refuse "the flags the wrong way round" "$H
a = ri\"a\"" "ir\"...\""
refuse "an unknown flag" "$H
a = ss\"a\"" "flags of a string"
refuse "a regular expression in a phrase rule" "top = r\"a+\" \"b\"" "\`name = r"
refuse "a leading zero" "$H
a = 0101" "leading zero"
refuse "%x in hbnf's notation" "$H
a = %x41" "0x41"
refuse "%x range in hbnf's notation" "$H
a = %x41-5A" "0x41..0x5A"
refuse "%d in hbnf's notation" "$H
a = %d65" "\`65\`"
refuse "%b in hbnf's notation" "$H
a = %b1000001" "0b1000001"
refuse "%d.d in hbnf's notation" "$H
a = %d13.10" "13 10"
refuse "%i in hbnf's notation" "$H
a = %i\"abc\"" "i\"...\""
refuse "%s in hbnf's notation" "$H
a = %s\"abc\"" "s\"...\""
refuse "a descending range" "$H
a = 0x5A..0x41" "other way round"
refuse "a number above Unicode" "$H
a = 0x110000" "0x10FFFF"
refuse "0x in ABNF" "dialect abnf
a = 0x41" "%x41"
refuse "i\"...\" in ABNF" "dialect abnf
a = i\"abc\"" "%i"
refuse "r\"...\" in ABNF" "dialect abnf
a = r\"a+\"" "no regular expressions"
accept "%x in ABNF" "dialect abnf
a = %x41-5A / %d97 / %b1100010 / %x63.64"
accept "%i in ABNF" "dialect abnf
a = %i\"abc\" / %s\"def\""
accept "a glued count" "$H
d = 48..57
a = 3d 2(\"x\") 1*2d"
accept "a range of characters" "$H
a = 'a'..'z' / 'A'-'Z' / 'é' / '\\x41' / '\\n' / '\\\\' / '\\''"
accept "a spaced run of code points" "$H
a = 65 66 0x43"
accept "%x in a rule of bit fields" "$H
a = len:8 payload:[len] %d13.10"

# A repetition the rest of a regular expression can begin like is reported in the regular expression's terms.
printf '%s\nwarn = r"a*a"\n' "$H" > "$W/g.hbnf"
"$CLI" "$W/g.hbnf" --backend=c > /dev/null 2> "$W/err"
grep -qF "can never match: the repetition takes every" "$W/err" \
	|| { echo "literal: FAIL (r\"a*a\" is not reported: $(head -c 300 "$W/err"))"; fail=1; }
grep -q "unlike ABNF" "$W/err" && { echo "literal: FAIL (r\"a*a\" is reported in ABNF's terms)"; fail=1; }
n=$((n + 1))
# tools/hbnf_modernize.py: tests/literal/old.txt becomes tests/literal/new.txt, and a second run has nothing to do.
if command -v python3 > /dev/null 2>&1; then
	cp tests/literal/old.txt "$W/t.txt"
	python3 tools/hbnf_modernize.py --check "$W/t.txt" > /dev/null \
		&& { echo "literal: FAIL (hbnf_modernize --check finds nothing to do in the old spellings)"; fail=1; }
	python3 tools/hbnf_modernize.py "$W/t.txt" > /dev/null
	cmp -s "$W/t.txt" tests/literal/new.txt \
		|| { echo "literal: FAIL (hbnf_modernize)"; diff tests/literal/new.txt "$W/t.txt" | head -10; fail=1; }
	python3 tools/hbnf_modernize.py --check "$W/t.txt" > /dev/null \
		|| { echo "literal: FAIL (hbnf_modernize is not idempotent)"; fail=1; }
	n=$((n + 1))
fi
[ $fail = 0 ] && echo "literal: OK ($nc inputs in the backends installed; the refusals and the old spellings checked)"
exit $fail
