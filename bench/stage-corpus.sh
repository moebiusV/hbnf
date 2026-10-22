#!/bin/sh
# stage-corpus.sh -- the compact node layout (the default) against the old one (--no-compact) on the
# repository's own corpora: JSON, Mustache, ALGOL 60 and the OpenBSD daemons' configs.  Each
# corpus's good files (the ones the grammar parses; a probe run drops the rest) are parsed
# REPS times with every tree kept, about 30 MB of input per row, so the figure for memory is
# what the trees hold.  Same generator, same grammar, same files; only the layout differs.
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
out=$RESULTS/corpus.md
cd /w

row() {   # row NAME GRAMMAR FILE...
	name=$1; g=$2; shift 2
	for v in old new; do
		flag=--no-compact; [ $v = new ] && flag=
		"$HBNF" "$g" --backend=c $flag > "$W/$name-$v.c" 2> "$W/$name.err" \
			|| { printf '| %s | | generate failed | | | |\n' "$name"; return; }
		outt=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$name-$v.c")
		[ -n "$outt" ] || { printf '| %s | | no parse_text | | | |\n' "$name"; return; }
		cat "$W/$name-$v.c" "$here/corpus/main.c" > "$W/$name-$v.m.c"
		gcc -O2 -std=gnu11 -D_GNU_SOURCE -w -DOUT_T="$outt" -I/w/tests/bsdinc "$W/$name-$v.m.c" -o "$W/$name-$v" 2> "$W/cc.err" \
			|| { printf '| %s | | compile failed: %s | | | |\n' "$name" "$(grep -m1 error "$W/cc.err" | cut -c1-80)"; return; }
	done
	good=""
	for f in "$@"; do "$W/$name-new" 1 "$f" > /dev/null 2>&1 && good="$good $f"; done
	[ -n "$good" ] || { printf '| %s | | no file parses | | | |\n' "$name"; return; }
	bytes=0; nf=0
	for f in $good; do bytes=$((bytes + $(wc -c < "$f"))); nf=$((nf + 1)); done
	reps=$((30000000 / (bytes > 0 ? bytes : 1))); [ $reps -lt 1 ] && reps=1; [ $reps -gt 20000 ] && reps=20000
	# the two layouts alternate, best of 9 each, so a busy host hits both alike
	o=""; n=""; i=0
	while [ $i -lt 9 ]; do
		a=$(best_of 1 "$W/$name-old" $reps $good) || { printf '| %s | | run failed (old) | | | |\n' "$name"; return; }
		b=$(best_of 1 "$W/$name-new" $reps $good) || { printf '| %s | | run failed (new) | | | |\n' "$name"; return; }
		if [ -z "$o" ] || awk -v x="${a%% *}" -v y="${o%% *}" 'BEGIN{exit !(x<y)}'; then o=$a; fi
		if [ -z "$n" ] || awk -v x="${b%% *}" -v y="${n%% *}" 'BEGIN{exit !(x<y)}'; then n=$b; fi
		i=$((i + 1))
	done
	set -- $o; oms=$1; orss=$2
	set -- $n; nms=$1; nrss=$2
	mkdir -p "$RESULTS/vals"
	awk -v k="$name" -v a="$oms" -v b="$nms" -v c="$orss" -v d="$nrss" 'BEGIN {
		printf "corpus_%s_old_ms=%.0f\ncorpus_%s_new_ms=%.0f\ncorpus_%s_old_rss_mb=%.0f\ncorpus_%s_new_rss_mb=%.0f\n", k, a, k, b, k, c/1024, k, d/1024 }' >> "$RESULTS/vals/corpus.txt"
	awk -v name="$name" -v nf="$nf" -v reps="$reps" -v by="$((bytes * reps))" -v a="$oms" -v b="$nms" -v c="$orss" -v d="$nrss" 'BEGIN {
		printf "| %s | %d files x %d | %.1f MB | %.0f ms | %.0f ms | %.2fx | %.0f MB | %.0f MB | %.2fx |\n",
		  name, nf, reps, by / 1e6, a, b, a / b, c / 1024, d / 1024, c / d }'
}

rm -f "$RESULTS/vals/corpus.txt"
{
	printf '| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |\n'
	printf '|---|---|---:|---:|---:|---:|---:|---:|---:|\n'
	row json corpus/json/json.hbnf corpus/json/tests/good/*.json
	row mustache corpus/mustache/mustache.hbnf corpus/mustache/tests/good/*.mustache
	row algol60 corpus/algol60/algol60.hbnf corpus/algol60/tests/good/*.a60
	for d in bgpd httpd ntpd pfctl relayd snmpd unwind; do
		row "$d" "grammars/obconf_$d.hbnf" tests/daemons/$d/*.conf
	done
	printf '\n'
	[ -f "$RESULTS/env.md" ] && printf '_%s_\n' "$(cat "$RESULTS/env.md")"
} > "$out"
