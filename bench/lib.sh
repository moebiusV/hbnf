# lib.sh — shared by the stages.  Source it; it needs $here (the bench dir),
# $RESULTS, $N_LIST and $RUNS from run.sh.

# best_of N CMD...: run CMD N times; print "ms rss count sum" of the fastest.
# Every run must print "ok BYTES COUNT SUM MS RSS"; anything else fails.
best_of() {
	n=$1; shift
	best=""
	i=0
	while [ "$i" -lt "$n" ]; do
		out=$("$@" 2> /dev/null | tail -1) || { echo "FAIL: $*" >&2; return 1; }
		line=$(printf '%s\n' "$out" | awk '$1 == "ok" { print $5, $6, $3, $4 }')
		[ -n "$line" ] || { echo "FAIL (no ok line): $* -> $out" >&2; return 1; }
		ms=${line%% *}
		if [ -z "$best" ] || awk -v a="$ms" -v b="${best%% *}" 'BEGIN{exit !(a<b)}'; then
			best=$line
		fi
		i=$((i + 1))
	done
	echo "$best"
}

# expect N: the COUNT and SUM gen.sh's toy file for N rules must give.
expect() {
	awk -v n="$1" 'BEGIN { s = 0; for (i = 1; i <= n; i++) s += 1000 + (i % 64536) + 443; print n, s }'
}

# row LABEL BYTES "ms rss count sum" N: one markdown table row, after checking
# the parse against expect().
row() {
	_label=$1; _bytes=$2; _got=$3; _n=$4
	set -- $_got
	ms=$1; rss=$2; count=$3; sum=$4
	want=$(expect "$_n")
	if [ "$count $sum" != "$want" ]; then
		printf '| %s | %s | WRONG: %s rules, sum %s (want %s) | | | |\n' \
			"$_label" "$_bytes" "$count" "$sum" "$want"
		return 1
	fi
	VAL=${VAL:-/dev/null}
	awk -v l="$_label" -v b="$_bytes" -v ms="$ms" -v rss="$rss" -v n="$_n" 'BEGIN {
		printf "| %s | %.2f MB | %s ms | %.1f M rules/s | %.0f MB/s | %.0f MB |\n",
		       l, b / 1e6, (ms < 10 ? sprintf("%.1f", ms) : sprintf("%.0f", ms)),
		       n / ms / 1000, b / 1e6 / (ms / 1000), rss / 1024
	}'
	# the same figures, raw, for the values the prose quotes (assemble.sh)
	awk -v b="$_bytes" -v ms="$ms" -v rss="$rss" -v n="$_n" 'BEGIN {
		printf "ms=%s\nmbytes=%.1f\nrss_mb=%.0f\nmrules=%.1f\nmbs=%.0f\nbytes_per_rule=%.0f\n",
		       (ms < 10 ? sprintf("%.1f", ms) : sprintf("%.0f", ms)), b / 1e6, rss / 1024,
		       n / ms / 1000, b / 1e6 / (ms / 1000), rss * 1024 / n
	}' > "$VAL" 2> /dev/null
}

# skipped_row LABEL WHY: a row for a tool that could not be run.
skipped_row() {
	printf '| %s | | skipped: %s | | | |\n' "$1" "$2"
}

table_head() {
	printf '| tool | input | parse time | rules/s | MB/s | peak RSS |\n'
	printf '|---|---:|---:|---:|---:|---:|\n'
}

# best_of_simple N CMD...: for a driver that prints "ok MS RSS" (time_conf.c).
best_of_simple() {
	n=$1; shift
	best_ms=""; best_rss=""
	i=0
	while [ "$i" -lt "$n" ]; do
		out=$("$@" 2> /dev/null | tail -1) || { echo "FAIL: $*" >&2; return 1; }
		ms=$(printf '%s\n' "$out" | awk '{print $(NF-1)}')
		rss=$(printf '%s\n' "$out" | awk '{print $NF}')
		if [ "$best_ms" = "" ] || awk -v a="$ms" -v b="$best_ms" 'BEGIN{exit !(a<b)}'; then
			best_ms=$ms; best_rss=$rss
		fi
		i=$((i + 1))
	done
	echo "$best_ms $best_rss"
}

# add_row N ORDER LABEL BYTES "ms rss count sum": keep one row of the toy table
# for N, in ORDER, for assemble.sh.
add_row() {
	n=$1; order=$2; label=$3; bytes=$4; got=$5
	mkdir -p "$RESULTS/rows/$n"
	echo "$bytes" > "$RESULTS/rows/$n/bytes"
	VAL="$RESULTS/rows/$n/$order.val" row "$label" "$bytes" "$got" "$n" > "$RESULTS/rows/$n/$order.md"
}

# add_skip N ORDER LABEL WHY
add_skip() {
	mkdir -p "$RESULTS/rows/$1"
	skipped_row "$3" "$4" > "$RESULTS/rows/$1/$2.md"
}

# add_edit_row N ORDER LABEL "ms rss count sum": a re-parse after an edit has no
# meaningful rules/s or MB/s (it reuses most of the old tree), so only the time
# and the memory are reported; the parse is still checked.
add_edit_row() {
	_en=$1; _eo=$2; _el=$3; _eg=$4
	mkdir -p "$RESULTS/rows/$_en"
	set -- $_eg
	want=$(expect "$_en")
	if [ "$3 $4" != "$want" ]; then
		printf '| %s | WRONG: %s rules, sum %s (want %s) | | | | |\n' "$_el" "$3" "$4" "$want" > "$RESULTS/rows/$_en/$_eo.md"
		return 1
	fi
	awk -v l="$_el" -v ms="$1" -v rss="$2" 'BEGIN {
		printf "| %s | (edit) | %s ms | | | %.0f MB |\n", l, (ms < 10 ? sprintf("%.1f", ms) : sprintf("%.0f", ms)), rss / 1024
	}' > "$RESULTS/rows/$_en/$_eo.md"
	awk -v ms="$1" -v rss="$2" 'BEGIN {
		printf "ms=%s\nrss_mb=%.0f\n", (ms < 10 ? sprintf("%.1f", ms) : sprintf("%.0f", ms)), rss / 1024
	}' > "$RESULTS/rows/$_en/$_eo.val"
}
