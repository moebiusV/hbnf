#!/bin/sh
# `=>` consequences (CONTEXTS.md section 30), as built: `set += tag` and `set -= tag` on a context, in the C backend.
# tests/consequence/names.hbnf is built with the checker of corpus/c/check.c and run on each case of its file (ok or
# bad); the other backends must refuse the grammar, by rule name.
#   HBNF=/path/to/hbnf sh tests/consequence.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
command -v cc > /dev/null 2>&1 || { echo "consequence: skipped (no C compiler)"; exit 0; }
fail=0
g=tests/consequence/names.hbnf
mkdir -p "$W/cases"; i=0
while IFS="$(printf '\t')" read -r want input; do
	i=$((i + 1)); printf '%b' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
done < tests/consequence/names-cases.txt
nc=$i
"$CLI" "$g" --backend=c > "$W/p.c" 2> "$W/err" \
	|| { echo "consequence: FAIL (does not generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/m.c" -o "$W/m" 2> "$W/cc.txt" \
	|| { echo "consequence: FAIL (the C does not compile: $(head -c 300 "$W/cc.txt"))"; exit 1; }
"$W/m" "$W"/cases/c*.txt > "$W/out" 2>&1
k=1
while [ $k -le $nc ]; do
	want=$(cat "$W/cases/c$k.want")
	got=$(grep -aF "c$k.txt" "$W/out" | head -1 | cut -d' ' -f1)
	[ -n "$got" ] || got=none
	[ "$got" = "$want" ] || { echo "consequence: FAIL (case $k, $(cut -f2 tests/consequence/names-cases.txt | sed -n "${k}p"): should be $want and is $got)"; fail=1; }
	k=$((k + 1))
done
# a consequence on a context is C only: the others refuse it, naming the rule
for b in rust zig; do
	"$CLI" "$g" --backend=$b 2>&1 > /dev/null | grep -q 'rule `stmt` has a consequence on a context' \
		|| { echo "consequence: FAIL ($b does not refuse it by rule name)"; fail=1; }
done
# (Ada refuses any grammar with a `context` already)
"$CLI" "$g" --backend=ada 2>&1 > /dev/null | grep -q 'a grammar with `context` can be emitted in C so far' \
	|| { echo "consequence: FAIL (ada does not refuse it)"; fail=1; }
# what is not built is refused with what is
printf 'prefix none\nwhitespace none\ndoc = "a" => 0\n' > "$W/v.hbnf"
"$CLI" "$W/v.hbnf" --backend=c 2>&1 > /dev/null | grep -q 'a value, a fact and `reread` are not built yet' \
	|| { echo "consequence: FAIL (a value is not refused with what is built)"; fail=1; }
printf 'prefix none\ncontext names\nwhitespace none\ndoc = "a" => names += N\n' > "$W/v.hbnf"
"$CLI" "$W/v.hbnf" --backend=c 2>&1 > /dev/null | grep -q 'no `as N` stands earlier' \
	|| { echo "consequence: FAIL (an unbound tag is not refused)"; fail=1; }
[ $fail = 0 ] && echo "consequence: ok ($nc cases, and the refusals)"
exit $fail
