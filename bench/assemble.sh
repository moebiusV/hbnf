#!/bin/sh
# assemble.sh — turn the rows the stages left into the tables the documents
# take (results/<name>.md).  Each table has one section per input size.
. "$here/lib.sh"

# mk NAME ORDER...: the rows with those orders, per N, under a heading.
mk() {
	name=$1; shift
	orders="$*"
	out=$RESULTS/$name.md
	: > "$out"
	for n in $(ls "$RESULTS/rows" 2> /dev/null | sort -n); do
		dir=$RESULTS/rows/$n
		files=""
		for o in $orders; do [ -f "$dir/$o.md" ] && files="$files $dir/$o.md"; done
		[ -n "$files" ] || continue
		bytes=$(awk '{printf "%.2f", $1 / 1e6}' "$dir/bytes")
		set -- $files
		if [ $# -gt 1 ]; then same=", the same file for every tool"; else same=""; fi
		printf '**%s rules** (%s MB%s):\n\n' \
			"$(echo "$n" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')" "$bytes" "$same" >> "$out"
		table_head >> "$out"
		for f in $files; do cat "$f" >> "$out"; done
		printf '\n' >> "$out"
	done
	[ -f "$RESULTS/env.md" ] && printf '_%s_\n' "$(cat "$RESULTS/env.md")" >> "$out"
}

mk toy            10 20 21 30 40 41 50 51 52
mk headline       10 20 21 40 50 51
mk hbnf-toy       10

# values.txt: every figure the prose quotes, NAME=value, for the inline
# <!-- v:NAME -->...<!-- /v --> markers.  NAME is TOOL_N_FIGURE.
tool_of() {
	case $1 in
	10) echo hbnf ;; 20) echo byacc ;; 21) echo bison ;; 30) echo peg ;;
	40) echo ts ;; 41) echo ts_edit ;; 50) echo antlr_cold ;; 51) echo antlr_warm ;;
	52) echo antlr_tree ;; *) echo "t$1" ;;
	esac
}
{
	for n in $(ls "$RESULTS/rows" 2> /dev/null | sort -n); do
		for v in "$RESULTS/rows/$n"/*.val; do
			[ -f "$v" ] || continue
			t=$(tool_of "$(basename "$v" .val)")
			sed "s/^/${t}_${n}_/" "$v"
		done
	done
	cat "$RESULTS"/vals/*.txt 2> /dev/null
} > "$RESULTS/values.txt"

# Ratios to hbnf (tool time / hbnf time), per size, appended to values.txt.
get() { sed -n "s/^$1=//p" "$RESULTS/values.txt" | head -1; }
for n in $(ls "$RESULTS/rows" 2> /dev/null | sort -n); do
	h=$(get "hbnf_${n}_ms")
	[ -n "$h" ] || continue
	for t in byacc bison peg ts ts_edit antlr_cold antlr_warm antlr_tree; do
		m=$(get "${t}_${n}_ms")
		[ -n "$m" ] || continue
		awk -v k="ratio_${t}_${n}" -v m="$m" -v h="$h" 'BEGIN {
			r = m / h
			printf "%s=%s\n", k, (r >= 10 ? sprintf("%.0f", r) : sprintf("%.1f", r))
		}' >> "$RESULTS/values.txt"
	done
done

# pfctl against the toy, per rule.
p=$(get pfctl_100000_ms); pr=$(get pfctl_100000_rss_mb); p1=$(get pfctl_1000000_rss_mb)
if [ -n "$p" ] && [ -n "$h" ]; then
	h1=$(get hbnf_100000_ms); hr=$(get hbnf_100000_rss_mb)
	awk -v p="$p" -v h="$h1" -v pr="$pr" -v hr="$hr" 'BEGIN {
		printf "pfctl_vs_toy_time=%.0f\npfctl_vs_toy_rss=%.0f\npfctl_100000_kb_per_rule=%.1f\n",
		       p / h, pr / hr, pr * 1024 / 100000
	}' >> "$RESULTS/values.txt"
fi
[ -n "$p1" ] && awk -v m="$p1" 'BEGIN { printf "pfctl_1000000_rss_gb=%.2f\n", m / 1024 }' >> "$RESULTS/values.txt"

# The pfctl table is written by its stage; give it the same conditions line.
if [ -f "$RESULTS/hbnf-pfctl.md" ] && [ -f "$RESULTS/env.md" ]; then
	grep -v '^_Measured' "$RESULTS/hbnf-pfctl.md" > "$RESULTS/hbnf-pfctl.tmp"
	{ cat "$RESULTS/hbnf-pfctl.tmp"; printf '\n_%s_\n' "$(cat "$RESULTS/env.md")"; } > "$RESULTS/hbnf-pfctl.md"
	rm -f "$RESULTS/hbnf-pfctl.tmp"
fi
