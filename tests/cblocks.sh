#!/bin/sh
# The interim route (LAYOUT.md): charts and codec tables written by C in the %emit blocks, preamble and epilogue of a
# grammar (examples/c-blocks/bitcharts.hbnf, the C backend), run over a grammar of leaf rules.  Its charts must draw the
# same rectangles and texts as the svg target's, and its tables must be the c-tables target's (same leaves; the order is
# the order of the file there, of the first rule here).   HBNF=/path/to/hbnf sh tests/cblocks.sh
set -u
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}; CC=${CC:-gcc}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
"$CLI" examples/c-blocks/bitcharts.hbnf --backend=c > "$T/bitcharts.c" 2> "$T/err" || { bad "generation: $(cat "$T/err")"; exit 1; }
cp examples/c-blocks/main.c "$T/"
$CC -O1 -I"$T" -o "$T/bitcharts" "$T/main.c" 2> "$T/cc" || { bad "cc: $(head -5 "$T/cc")"; exit 1; }
for g in examples/mini.hbnf examples/pdp64/pdp64-16/pdp64-16.hbnf examples/pdp64/pdp64-32/pdp64-32.hbnf; do
	n=$(basename "$g" .hbnf)
	mkdir -p "$T/c-$n" "$T/t-$n"
	"$T/bitcharts" "$T/c-$n" < "$g" 2> "$T/log" || { bad "$n: $(head -3 "$T/log")"; continue; }
	"$CLI" "$g" --target=svg --out="$T/t-$n" 2> /dev/null
	rm -f "$T/t-$n/index.html"
	r=$(python3 -I tests/svgcmp.py "$T/c-$n" "$T/t-$n")
	case $r in *" 0 differ"*) ok "$n: C blocks draw what the svg target draws ($r)";; *) bad "$n: $r";; esac
done
# the same C route writes the tables
"$T/bitcharts" "$T" tables < examples/pdp64/pdp64-16/pdp64-16.hbnf 2> /dev/null | grep -q 'static const struct lleaf LF' && ok "tables are written" || bad "tables are written"
# an action on the encoding's own rules cannot draw: it sees values, not layout (documented in the file; here only that it runs)
"$CLI" examples/c-blocks/sample-driven.hbnf --backend=c > "$T/sample-driven.c" 2> /dev/null && cp examples/c-blocks/sample-main.c "$T/" && $CC -I"$T" -o "$T/sd" "$T/sample-main.c" 2> /dev/null && "$T/sd" | grep -q 'restated by hand' && ok "sample-driven actions run (and see values only)" || bad "sample-driven"
[ "$fail" = 0 ] && echo "cblocks: OK" || { echo "cblocks: $fail failed"; exit 1; }
