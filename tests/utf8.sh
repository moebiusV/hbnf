#!/bin/sh
# What the generated parser takes for a code point (CONTEXTS.md section 26, item 21): tests/utf8/utf8.hbnf is a
# rule of characters over the whole range, and each case of tests/utf8/cases.txt (a verdict, ok or bad, and the
# bytes, as printf %b writes them: octal, \0ooo, since sh may be dash) is given to the C parser built with the checker of corpus/c/check.c.  An
# overlong form, a surrogate or a value past U+10FFFF must be refused, as a stray byte is.
#   HBNF=/path/to/hbnf sh tests/utf8.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
command -v cc > /dev/null 2>&1 || { echo "utf8: skipped (no C compiler)"; exit 0; }
fail=0
mkdir -p "$W/cases"; i=0
while IFS="$(printf '\t')" read -r want input; do
	i=$((i + 1)); printf '%b' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
done < tests/utf8/cases.txt
nc=$i
"$CLI" tests/utf8/utf8.hbnf --backend=c > "$W/p.c" 2> "$W/err" \
	|| { echo "utf8: FAIL (does not generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/m.c" -o "$W/m" 2> "$W/cc.txt" \
	|| { echo "utf8: FAIL (the C does not compile: $(head -c 300 "$W/cc.txt"))"; exit 1; }
"$W/m" "$W"/cases/c*.txt > "$W/out" 2>&1
k=1
while [ $k -le $nc ]; do
	want=$(cat "$W/cases/c$k.want")
	got=$(grep -aF "c$k.txt" "$W/out" | head -1 | cut -d' ' -f1)
	[ -n "$got" ] || got=none
	[ "$got" = "$want" ] || { echo "utf8: FAIL (bytes of case $k: should be $want and is $got: $(sed -n "$((k))p" tests/utf8/cases.txt | cut -f2))"; fail=1; }
	k=$((k + 1))
done
[ $fail = 0 ] && echo "utf8: ok ($nc cases)"
exit $fail
