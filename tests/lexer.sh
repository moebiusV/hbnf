#!/bin/sh
# The reader's character literals: `'\'` is a backslash (a backslash directly before the closing quote), `'\''` is an escaped quote
# (item 2); a lookahead over `'c'` works (item 1: what the string does; `'c'` stays a code point where it is read otherwise).  tests/lexer/backslash.hbnf and chars.hbnf are built (C).
#   HBNF=/path/to/hbnf sh tests/lexer.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
command -v cc > /dev/null 2>&1 || { echo "lexer: skipped (no C compiler)"; exit 0; }
fail=0
"$CLI" tests/lexer/backslash.hbnf --backend=c > "$W/p.c" 2> "$W/err" || { echo "lexer: FAIL (backslash.hbnf: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/m.c" -o "$W/check" 2> "$W/cc.txt" || { echo "lexer: FAIL (cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
t() {   # WANT TEXT
	printf '%s' "$2" > "$W/t.txt"
	got=$("$W/check" "$W/t.txt" | cut -d' ' -f1)
	[ "$got" = "$1" ] || { echo "lexer: FAIL ([$2] should be $1 and is $got)"; fail=1; }
}
t ok '\'
t ok "'"
t ok '"'
t ok "\\'\"\\"
t ok ''
t bad 'x'
# 'c' is "c"
"$CLI" tests/lexer/chars.hbnf --backend=c > "$W/q.c" 2> "$W/err" || { echo "lexer: FAIL (chars.hbnf: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/q.c")
cat "$W/q.c" corpus/c/check.c > "$W/mq.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/mq.c" -o "$W/checkq" 2> "$W/cc.txt" || { echo "lexer: FAIL (chars.hbnf: cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
q() {   # WANT TEXT
	printf '%s' "$2" > "$W/t.txt"
	got=$("$W/checkq" "$W/t.txt" | cut -d' ' -f1)
	[ "$got" = "$1" ] || { echo "lexer: FAIL (chars: [$2] should be $1 and is $got)"; fail=1; }
}
q ok 'ac'
q ok '--ac---'
q bad 'ab'
q bad 'a'
q bad 'acc'
# a lookahead over a sequence (item 3)
"$CLI" tests/lexer/look-sequence.hbnf --backend=c > "$W/s.c" 2> "$W/err" || { echo "lexer: FAIL (look-sequence.hbnf: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/s.c")
cat "$W/s.c" corpus/c/check.c > "$W/ms.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/ms.c" -o "$W/checks" 2> "$W/cc.txt" || { echo "lexer: FAIL (look-sequence.hbnf: cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
for c in "ok ac" "bad ab"; do
	printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/checks" "$W/t.txt" | cut -d' ' -f1)
	[ "$got" = "${c%% *}" ] || { echo "lexer: FAIL (!( \"a\" \"b\" ) on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
done
# a hyperrule's literal argument under `sensitivity string %i` (item 23)
"$CLI" tests/lexer/hyper-case.hbnf --backend=c > "$W/h.c" 2> /dev/null || { echo "lexer: FAIL (hyper-case.hbnf does not generate)"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/h.c")
cat "$W/h.c" corpus/c/check.c > "$W/mh.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/mh.c" -o "$W/checkh" 2> "$W/cc.txt" || { echo "lexer: FAIL (hyper-case.hbnf: cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
for c in "ok <a><b>" "ok <A><B>" "ok <a><B>" "bad <a><c>"; do
	printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/checkh" "$W/t.txt" | cut -d' ' -f1)
	[ "$got" = "${c%% *}" ] || { echo "lexer: FAIL (f(\"a\") under %i on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
done
# a `word` renamed `word-rule` is still the keyword boundary (item 13)
"$CLI" tests/lexer/word-group.hbnf --backend=c > "$W/w.c" 2> /dev/null || { echo "lexer: FAIL (word-group.hbnf does not generate)"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/w.c")
cat "$W/w.c" corpus/c/check.c > "$W/mw.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/mw.c" -o "$W/checkw" 2> "$W/cc.txt" || { echo "lexer: FAIL (word-group.hbnf: cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
for c in "ok if abc" "ok if a-b" "bad ifx abc"; do
	printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/checkw" "$W/t.txt" | cut -d' ' -f1)
	[ "$got" = "${c%% *}" ] || { echo "lexer: FAIL (word-group on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
done
# a token exception with a literal operand (item 14)
"$CLI" tests/lexer/except-literal.hbnf --backend=c > "$W/e.c" 2> "$W/err" || { echo "lexer: FAIL (except-literal.hbnf: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/e.c")
cat "$W/e.c" corpus/c/check.c > "$W/me.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/me.c" -o "$W/checke" 2> "$W/cc.txt" || { echo "lexer: FAIL (except-literal.hbnf: cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
for c in "ok abc xy" "bad abc on" "ok onx a" "bad on"; do
	printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/checke" "$W/t.txt" | cut -d' ' -f1)
	[ "$got" = "${c%% *}" ] || { echo "lexer: FAIL (name - \"on\" on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
done
# Ada names (items 9 and 18): the generated text has no value named like its type and no `__`; compiled where gnatmake is
for g in ada-type-literal ada-instance-name; do
	"$CLI" tests/lexer/$g.hbnf --backend=ada --package=Tl > "$W/$g.ada" 2> "$W/err" || { echo "lexer: FAIL ($g, Ada: $(head -c 300 "$W/err"))"; fail=1; continue; }
	grep -Eq 'is \(Kw_Type,|[A-Za-z0-9]__' "$W/$g.ada" && { echo "lexer: FAIL ($g, Ada: a value named like its type, or a double underscore)"; fail=1; }
	if command -v gnatmake > /dev/null 2>&1 && command -v gnatchop > /dev/null 2>&1; then
		mkdir -p "$W/ad-$g"; cp "$W/$g.ada" "$W/ad-$g/all.ada"
		(cd "$W/ad-$g" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -c -gnat2022 -gnatws *.adb > cc.txt 2>&1) \
			|| { echo "lexer: FAIL ($g does not compile in Ada: $(grep -m2 error "$W/ad-$g/cc.txt" | head -c 300))"; fail=1; }
	fi
done
# Rust: a capture under -D warnings (items 20 and 32), and a lookahead that skips white space first, as C does
if command -v rustc > /dev/null 2>&1; then
	mkdir -p "$W/rl"
	sed "s/MODULE/l/g" corpus/c/check.rs > "$W/rl/m.rs"
	"$CLI" tests/lexer/rust-capture.hbnf --backend=rust > "$W/rl/l.rs" 2> "$W/err" || { echo "lexer: FAIL (rust-capture: $(head -c 300 "$W/err"))"; fail=1; }
	(cd "$W/rl" && rustc --edition 2021 -D warnings -o m m.rs > cc.txt 2>&1) \
		|| { echo "lexer: FAIL (a capture does not compile in Rust under -D warnings: $(grep -m2 error "$W/rl/cc.txt" | head -c 300))"; fail=1; }
	"$CLI" tests/lexer/look-ws.hbnf --backend=rust > "$W/rl/l.rs" 2> "$W/err" || { echo "lexer: FAIL (look-ws: $(head -c 300 "$W/err"))"; fail=1; }
	(cd "$W/rl" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1) || { echo "lexer: FAIL (look-ws does not compile in Rust)"; fail=1; }
	printf 'PROCESS a b IDENTIFICATION X' > "$W/rl/in.txt"
	[ "$("$W/rl/m" "$W/rl/in.txt" 2>&1 | cut -d' ' -f1)" = ok ] \
		|| { echo "lexer: FAIL (look-ws: Rust does not stop a list at the word the lookahead names)"; fail=1; }
fi
# two rules that become one identifier are refused, naming both (R636: the mangling of names), in each backend
for be in c rust zig ada; do
	"$CLI" tests/lexer/name-collision.hbnf --backend=$be --package=Tn > /dev/null 2> "$W/err" \
		&& { echo "lexer: FAIL (name-collision, $be: generated, should be refused)"; fail=1; continue; }
	grep -q 'rules `and-like-this` and `and_like_this` both become' "$W/err" \
		|| { echo "lexer: FAIL (name-collision, $be: the message does not name both rules: $(head -c 200 "$W/err"))"; fail=1; }
done
# a hyperrule in an island's guest (item 27)
"$CLI" tests/lexer/island-host.hbnf --backend=c > "$W/i.c" 2> "$W/err" || { echo "lexer: FAIL (island-host.hbnf: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/i.c")
cat "$W/i.c" corpus/c/check.c > "$W/mi.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/mi.c" -o "$W/checki" 2> "$W/cc.txt" || { echo "lexer: FAIL (island-host.hbnf: cc: $(head -c 300 "$W/cc.txt"))"; exit 1; }
for c in "ok <a b a>" "ok <>" "bad <c>"; do
	printf '%s' "${c#* }" > "$W/t.txt"; got=$("$W/checki" "$W/t.txt" | cut -d' ' -f1)
	[ "$got" = "${c%% *}" ] || { echo "lexer: FAIL (island hyperrule on [${c#* }] should be ${c%% *} and is $got)"; fail=1; }
done
# a rule named `text` (item 26) in Rust, where it is installed
if command -v rustc > /dev/null 2>&1; then
	mkdir -p "$W/rs"
	"$CLI" tests/lexer/text-rule.hbnf --backend=rust > "$W/rs/l.rs" 2> "$W/err" || { echo "lexer: FAIL (text rule, Rust: $(head -c 300 "$W/err"))"; fail=1; }
	sed "s/MODULE/l/g" corpus/c/check.rs > "$W/rs/m.rs"
	(cd "$W/rs" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1) || { echo "lexer: FAIL (a rule named text does not compile in Rust: $(head -c 300 "$W/rs/cc.txt"))"; fail=1; }
fi
[ $fail = 0 ] || exit 1
echo "lexer: OK (a backslash before the closing quote is a backslash, an escaped quote is still one; a lookahead over 'c' and a repetition of it)"
