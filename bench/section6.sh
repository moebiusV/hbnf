#!/bin/sh
# section6.sh — re-measure §6 of USENIXSUBMISSION.md.
#
#   - toy schema (bench/toy.hbnf): parse_text, 100,000 and 1,000,000 rules.
#   - pfctl grammar (grammars/pfctl.hbnf, --conf): parse_config, 100,000 rules.
#
# The parsers are compiled with gcc -O2.  Each parse runs in its own process,
# five times; the reported time is the best of the five, wall-clock around the
# parse call, and memory is getrusage's ru_maxrss (KiB).
#
#   HBNF_CLI=/path/to/hbnf_cli sh bench/section6.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$root/templates}"
CLI=${HBNF_CLI:-$root/hbnf_cli}

# best_of N CMD...: run CMD N times, print "time_ms rss_kib" of the fastest.
best_of() {
	n=$1; shift
	best_ms=""; best_rss=""
	i=0
	while [ "$i" -lt "$n" ]; do
		out=$("$@" 2>/dev/null) || { echo "FAIL: $*" >&2; return 1; }
		# out is "ok BYTES MS RSS" (toy) or "ok MS RSS" (pfctl); the
		# last two fields are always the wall time and peak RSS.
		ms=$(printf '%s\n' "$out" | awk '{print $(NF-1)}')
		rss=$(printf '%s\n' "$out" | awk '{print $NF}')
		if [ "$best_ms" = "" ] || awk -v a="$ms" -v b="$best_ms" 'BEGIN{exit !(a<b)}'; then
			best_ms=$ms; best_rss=$rss
		fi
		i=$((i + 1))
	done
	echo "$best_ms $best_rss"
}

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# --- toy: parse_text -------------------------------------------------------
"$CLI" "$here/toy.hbnf" --backend=c > "$W/toy.c" 2> "$W/toy.err" \
	|| { echo "toy: generate failed"; cat "$W/toy.err"; exit 1; }
cp "$W/toy.c" "$W/parser.c"
if ! gcc -O2 -std=gnu11 -I"$W" "$here/time_text.c" -o "$W/toy" 2> "$W/cc.err"; then
	echo "toy: compile failed"; grep -m5 error "$W/cc.err"; exit 1
fi

for n in 100000 1000000; do
	"$here/gen.sh" toy "$n" > "$W/toy.conf"
	b=$(wc -c < "$W/toy.conf")
	best=$(best_of 5 "$W/toy" "$W/toy.conf") || exit 1
	echo "toy $n: ${b} bytes, ${best} ms / KiB"
done

# --- pfctl: parse_config ---------------------------------------------------
"$CLI" "$root/grammars/pfctl.hbnf" --backend=c --conf > "$W/conf.txt" 2> "$W/pfctl.err" \
	|| { echo "pfctl: generate failed"; cat "$W/pfctl.err"; exit 1; }
awk '/^===== conf.h =====$/{f="h"; next} /^===== conf.c =====$/{f="c"; next} f=="h"{print > "'"$W"'/conf.h"} f=="c"{print > "'"$W"'/conf.c"}' "$W/conf.txt"
if ! gcc -O2 -std=gnu11 -I"$W" -I"$root/tests/bsdinc" "$W/conf.c" "$here/time_conf.c" -o "$W/pfctl" 2> "$W/cc.err"; then
	echo "pfctl: compile failed"; grep -m5 error "$W/cc.err"; exit 1
fi

"$here/gen.sh" pfctl 100000 > "$W/pfctl.conf"
b=$(wc -c < "$W/pfctl.conf")
best=$(best_of 5 "$W/pfctl" "$W/pfctl.conf") || exit 1
echo "pfctl 100000: ${b} bytes, ${best} ms / KiB"
