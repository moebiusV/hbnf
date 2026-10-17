#!/bin/sh
# stage-hbnf.sh — hbnf's own generated C parser: the toy (parse_text) at each N,
# and the full pfctl grammar through the --conf wrapper (parse_file).
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rm -f "$RESULTS"/rows/*/10.md "$RESULTS"/vals/pfctl.txt

(cd "$here" && "$HBNF" toy.hbnf --backend=c) > "$W/parser.c" 2> "$W/gen.err" \
	|| { echo "hbnf: generate failed"; cat "$W/gen.err"; exit 1; }
gcc -O2 -std=gnu11 -I"$W" -I"$here/drv" "$here/drv/hbnf_toy.c" -o "$W/toy" 2> "$W/cc.err" \
	|| { echo "hbnf: compile failed"; head -5 "$W/cc.err"; exit 1; }
for n in $N_LIST; do
	bytes=$(wc -c < "$IN/toy-$n.txt")
	got=$(best_of "$RUNS" "$W/toy" "$IN/toy-$n.txt") || exit 1
	add_row "$n" 10 "hbnf (C backend)" "$bytes" "$got"
done

# ---- pfctl: the whole grammar, parse_file ----------------------------------
"$HBNF" /w/grammars/obconf_pfctl.hbnf --backend=c --conf > "$W/conf.txt" 2> "$W/pfctl.err" \
	|| { echo "pfctl: generate failed"; cat "$W/pfctl.err"; exit 1; }
awk '/^===== conf.h =====$/{f="h"; next} /^===== conf.c =====$/{f="c"; next}
     f=="h"{print > "'"$W"'/conf.h"} f=="c"{print > "'"$W"'/conf.c"}' "$W/conf.txt"
gcc -O2 -std=gnu11 -I"$W" -I/w/tests/bsdinc "$W/conf.c" "$here/time_conf.c" -o "$W/pfctl" 2> "$W/cc.err" \
	|| { echo "pfctl: compile failed"; grep -m5 error "$W/cc.err"; exit 1; }
{
	printf '| rules | input | parse time | rules/s | MB/s | peak RSS |\n'
	printf '|---:|---:|---:|---:|---:|---:|\n'
	for n in $N_LIST; do
		"$here/gen.sh" pfctl "$n" > "$IN/pfctl-$n.txt"
		bytes=$(wc -c < "$IN/pfctl-$n.txt")
		best=$(best_of_simple "$RUNS" "$W/pfctl" "$IN/pfctl-$n.txt") || exit 1
		set -- $best
		mkdir -p "$RESULTS/vals"
		awk -v n="$n" -v ms="$1" -v rss="$2" 'BEGIN {
			printf "pfctl_%s_ms=%.0f\npfctl_%s_s=%.1f\npfctl_%s_rss_mb=%.0f\n", n, ms, n, ms/1000, n, rss/1024
		}' >> "$RESULTS/vals/pfctl.txt"
		awk -v n="$n" -v b="$bytes" -v ms="$1" -v rss="$2" 'BEGIN {
			printf "| %s | %.2f MB | %s | %.0f K rules/s | %.0f MB/s | %s |\n",
			  n, b/1e6, (ms < 1000 ? sprintf("%.0f ms", ms) : sprintf("%.2f s", ms/1000)),
			  n/ms, b/1e6/(ms/1000), (rss >= 1048576 ? sprintf("%.1f GB", rss/1048576) : sprintf("%.0f MB", rss/1024))
		}' | sed 's/ MB |$/ MB |/'
	done
} > "$RESULTS/hbnf-pfctl.md"
