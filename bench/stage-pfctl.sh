#!/bin/sh
# stage-pfctl.sh -- a real, large parse.y: OpenBSD's sbin/pfctl/parse.y at a pinned commit,
# unmodified, through byacc, against hbnf's translation of the same grammar
# (grammars/obconf_pfctl.hbnf).  The same file of N filter rules goes to both and each is
# checked to have found N of them.
#
# What each side does with a rule is not the same, and the table says so: parse.y runs its
# actions (it fills a struct pf_rule per rule and hands it to a stub of pfctl_add_rule that
# copies and lists it, as pfctl's does); hbnf builds the typed tree and keeps it, and runs no
# semantic code.  So the comparison is "parse.y as it is" against "the grammar and its tree".
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cache=$here/cache/pfctl
mkdir -p "$cache"
out=$RESULTS/pfctl_yacc.md
rm -f "$RESULTS/vals/pfctl_yacc.txt"
head_row() { printf '| tool | input | parse time | rules/s | MB/s | peak RSS |\n|---|---|---:|---:|---:|---:|\n'; }
skip() {
	{ head_row
	  printf '| OpenBSD pfctl parse.y + byacc | | skipped: %s | | | |\n' "$1"
	  printf '| hbnf pfctl grammar (`--conf`) | | skipped: %s | | | |\n' "$1"
	} > "$out"
	exit 0
}
while read -r path sha; do
	f=$cache/$path
	mkdir -p "$(dirname "$f")"
	if [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ]; then continue; fi
	wget -q -O "$f" "https://raw.githubusercontent.com/openbsd/src/$PARSEY_COMMIT/$path" \
		|| skip "could not fetch $path at $PARSEY_COMMIT"
	[ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ] || skip "$path does not match its recorded sha256"
done < "$here/pfctl/files.txt"

export PFCTL_SRC=$cache
sh "$here/pfctl/build-parsey.sh" "$W/y" > "$W/y.err" 2>&1 || skip "parse.y build failed: $(grep -m1 -E 'error|undefined' "$W/y.err" | cut -c1-100)"
"$HBNF" /w/grammars/obconf_pfctl.hbnf --backend=c --conf > "$W/conf.txt" 2> "$W/h.err" || skip "hbnf generate failed"
awk '/^===== conf.h =====$/{f="h"; next} /^===== conf.c =====$/{f="c"; next}
     f=="h"{print > "'"$W"'/conf.h"} f=="c"{print > "'"$W"'/conf.c"}' "$W/conf.txt"
cat "$W/conf.c" "$here/pfctl/time_hbnf.c" > "$W/h.c"
gcc -O2 -std=gnu11 -I"$W" -I/w/tests/bsdinc "$W/h.c" -o "$W/hbnfp" 2> "$W/h.err" \
	|| skip "hbnf parser build failed: $(grep -m1 error "$W/h.err" | cut -c1-100)"

pf_row() {   # pf_row LABEL BINARY N KEY CHECKSUM
	label=$1; bin=$2; n=$3; key=$4; chk=$5; f=$IN/pfctl-$n.txt
	bytes=$(wc -c < "$f")
	got=$(best_of "$RUNS" "$bin" "$f") || { printf '| %s | | run failed | | | |\n' "$label"; return; }
	set -- $got
	if [ "$3" != "$n" ] || { [ "$chk" = sum ] && [ "$4" != "$(awk -v n="$n" 'BEGIN{s=0;for(i=1;i<=n;i++)s+=1000+(i%64536);print s}')" ]; }; then
		printf '| %s | | WRONG: %s rules, sum %s | | | |\n' "$label" "$3" "$4"; return
	fi
	mkdir -p "$RESULTS/vals"
	awk -v k="$key" -v n="$n" -v ms="$1" -v rss="$2" 'BEGIN {
		printf "pfctl_%s_%s_ms=%.0f\npfctl_%s_%s_rss_mb=%.1f\n", k, n, ms, k, n, rss/1024 }' >> "$RESULTS/vals/pfctl_yacc.txt"
	awk -v l="$label" -v b="$bytes" -v n="$n" -v ms="$1" -v rss="$2" 'BEGIN {
		printf "| %s | %.2f MB | %s | %.0f K rules/s | %.0f MB/s | %.1f MB |\n", l, b/1e6,
		  (ms < 1000 ? sprintf("%.0f ms", ms) : sprintf("%.2f s", ms/1000)), n/ms, b/1e6/(ms/1000), rss/1024 }'
}
{
	for n in $N_LIST; do
		"$here/gen.sh" pfctl "$n" > "$IN/pfctl-$n.txt"
		printf '**%s filter rules** (one `pass in quick ... keep state` line each, the same file for both):\n\n' "$(echo "$n" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')"
		head_row
		pf_row "OpenBSD pfctl parse.y, byacc (fills struct pf_rule)" "$W/y/parsey" "$n" byacc sum
		pf_row "hbnf pfctl grammar (\`--conf\`, typed tree)" "$W/hbnfp" "$n" hbnf nosum
		printf '\n'
	done
	[ -f "$RESULTS/env.md" ] && printf '_%s_\n' "$(cat "$RESULTS/env.md")"
} > "$out"
