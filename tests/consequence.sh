#!/bin/sh
# `=>` consequences (CONTEXTS.md section 30), as built, in the C backend:
#   names.hbnf   `set += tag` and `set -= tag` on a context
#   macros.hbnf  facts (`tag.attr = tag`) and a rewrite (`=> template [with tag.attr = tag]`): the match is replaced
#                and the parse starts again on the new text
# Each grammar is built with the checker of corpus/c/check.c and run on each case of its file (ok or bad); the other
# backends must refuse them, by rule name.
#   HBNF=/path/to/hbnf sh tests/consequence.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
command -v cc > /dev/null 2>&1 || { echo "consequence: skipped (no C compiler)"; exit 0; }
fail=0; total=0

# run NAME RULE: the cases of tests/consequence/NAME-cases.txt on the parser of NAME.hbnf; the other backends refuse
# it, naming RULE (none: a grammar with code of its own, which they refuse for another reason)
run() {
	n=$1; r=$2; g=tests/consequence/$n.hbnf; d=$W/$n
	mkdir -p "$d/cases"; i=0
	while IFS="$(printf '\t')" read -r want input; do
		i=$((i + 1)); printf '%b' "$input" > "$d/cases/c$i.txt"; echo "$want" > "$d/cases/c$i.want"
	done < tests/consequence/$n-cases.txt
	nc=$i; total=$((total + nc))
	"$CLI" "$g" --backend=c > "$d/p.c" 2> "$d/err" \
		|| { echo "consequence: FAIL ($n does not generate: $(head -c 300 "$d/err"))"; fail=1; return; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$d/p.c")
	cat "$d/p.c" corpus/c/check.c > "$d/m.c"
	cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$d/m.c" -o "$d/m" 2> "$d/cc.txt" \
		|| { echo "consequence: FAIL ($n: the C does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; return; }
	"$d/m" "$d"/cases/c*.txt > "$d/out" 2>&1
	k=1
	while [ $k -le $nc ]; do
		want=$(cat "$d/cases/c$k.want")
		got=$(grep -aF "c$k.txt" "$d/out" | head -1 | cut -d' ' -f1)
		[ -n "$got" ] || got=none
		[ "$got" = "$want" ] || { echo "consequence: FAIL ($n case $k, $(cut -f2 tests/consequence/$n-cases.txt | sed -n "${k}p"): should be $want and is $got)"; fail=1; }
		k=$((k + 1))
	done
	[ -n "$r" ] || return
	for b in rust zig; do
		"$CLI" "$g" --backend=$b 2>&1 > /dev/null | grep -q "rule \`$r\` has a consequence on a context, a fact or a rewrite" \
			|| { echo "consequence: FAIL ($n: $b does not refuse it by rule name)"; fail=1; }
	done
	# (Ada refuses any grammar with a `context` already)
	"$CLI" "$g" --backend=ada 2>&1 > /dev/null | grep -q 'a grammar with `context` can be emitted in C so far' \
		|| { echo "consequence: FAIL ($n: ada does not refuse it)"; fail=1; }
}
run names stmt
run macros define
run fn ''

# what is not read is refused with what is
refused() {   # refused TEXT PATTERN
	printf 'prefix none\ncontext names\nwhitespace none\n%s\n' "$1" > "$W/v.hbnf"
	"$CLI" "$W/v.hbnf" --backend=c 2>&1 > /dev/null | grep -q "$2" \
		|| { echo "consequence: FAIL (not refused with \"$2\": $1)"; fail=1; }
}
refused 'doc = "a" => names += N' 'no `as N` stands earlier'
refused 'doc = "a" => "x" N' 'no `as N` stands earlier'
refused 'doc = "a" => 0' 'no `as 0` stands earlier'
refused 'doc = "a" as T => T.attr = Q' 'no `as Q` stands earlier'
refused 'doc = "a" as T => T = T' 'is not `tag.attribute`'
[ $fail = 0 ] && echo "consequence: ok ($total cases, and the refusals)"
exit $fail
