#!/bin/sh
# stage-ntpd.sh — a real parse.y: OpenBSD's ntpd parse.y at a pinned commit,
# unmodified, through byacc, against hbnf's binding of the same language
# (grammars/bind/ntpd.hbnf).  Both fill ntpd's own `struct ntpd_conf` from an
# N-sensor config and are checked to have built the same sensors.
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cache=$here/cache/ntpd
mkdir -p "$cache"
out=$RESULTS/ntpd.md
rm -f "$RESULTS/vals/ntpd.txt"

skip() {
	{ table_head_ntpd
	  printf '| OpenBSD ntpd parse.y + byacc | | skipped: %s | | | |\n' "$1"
	  printf '| hbnf ntpd binding | | skipped: %s | | | |\n' "$1"
	} > "$out"
	exit 0
}
table_head_ntpd() {
	printf '| tool | input | parse time | sensors/s | MB/s | peak RSS |\n'
	printf '|---|---:|---:|---:|---:|---:|\n'
}

# The sources, fetched once and checked against the recorded hashes.
while read -r path sha; do
	f=$cache/$(basename "$path")
	if [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ]; then continue; fi
	wget -q -O "$f" "https://raw.githubusercontent.com/openbsd/src/$NTPD_COMMIT/$path" \
		|| skip "could not fetch $path at $NTPD_COMMIT"
	[ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ] || skip "$path does not match its recorded sha256"
done < "$here/ntpd/files.txt"

export NTPD_SRC=$cache
sh "$here/ntpd/build-parsey.sh" "$W/y" > "$W/y.err" 2>&1 || skip "parse.y build failed: $(grep -m1 -E 'error|undefined' "$W/y.err" | cut -c1-100)"
sh "$here/ntpd/build-hbnf.sh" "$W/h" > "$W/h.err" 2>&1 || skip "binding build failed: $(grep -m1 -E 'error|undefined|hbnf:' "$W/h.err" | cut -c1-100)"

ntpd_row() {   # ntpd_row LABEL BINARY N KEY
	label=$1; bin=$2; n=$3; key=$4; f=$IN/ntpd-$n.conf
	bytes=$(wc -c < "$f")
	got=$(best_of "$RUNS" "$bin" "$f") || { printf '| %s | | run failed | | | |\n' "$label"; return; }
	set -- $got
	want=$(awk -v n="$n" 'BEGIN { s = 0; for (i = 1; i <= n; i++) s += 1 + (i % 15); print n, s }')
	if [ "$3 $4" != "$want" ]; then
		printf '| %s | | WRONG: %s sensors, stratum sum %s (want %s) | | | |\n' "$label" "$3" "$4" "$want"
		return
	fi
	mkdir -p "$RESULTS/vals"
	awk -v k="$key" -v n="$n" -v ms="$1" -v rss="$2" 'BEGIN {
		printf "ntpd_%s_%s_ms=%.0f\nntpd_%s_%s_rss_mb=%.1f\n", k, n, ms, k, n, rss/1024
	}' >> "$RESULTS/vals/ntpd.txt"
	awk -v l="$label" -v b="$bytes" -v n="$n" -v ms="$1" -v rss="$2" 'BEGIN {
		printf "| %s | %.2f MB | %s | %.0f K sensors/s | %.0f MB/s | %.1f MB |\n", l, b/1e6,
		  (ms < 1000 ? sprintf("%.0f ms", ms) : sprintf("%.2f s", ms/1000)), n/ms, b/1e6/(ms/1000), rss/1024
	}'
}

{
	for n in $N_LIST; do
		awk -v n="$n" 'BEGIN {
			for (i = 1; i <= n; i++)
				printf "sensor nmea%d correction %d refid GPS stratum %d weight %d\n",
				       i, 100 + (i % 900), 1 + (i % 15), 1 + (i % 10)
		}' > "$IN/ntpd-$n.conf"
		printf '**%s sensors** (one `sensor` line each, the same file for both):\n\n' "$(echo "$n" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')"
		table_head_ntpd
		ntpd_row "OpenBSD ntpd parse.y, byacc" "$W/y/parsey" "$n" byacc
		ntpd_row "hbnf binding (\`--conf\`)" "$W/h/hbnfd" "$n" hbnf
		printf '\n'
	done
	[ -f "$RESULTS/env.md" ] && printf '_%s_\n' "$(cat "$RESULTS/env.md")"
} > "$out"
