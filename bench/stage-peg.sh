#!/bin/sh
# stage-peg.sh — the toy as a PEG, with Piumarta's peg/leg (compare/toy.leg).
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rm -f "$RESULTS"/rows/*/30-*.md
label="peg/leg"
cp "$here/compare/toy.leg" "$W/"
if ! (cd "$W" && leg -o toy.c toy.leg && gcc -O2 -std=gnu11 -w -I"$here/drv" toy.c -o toy) > "$W/build.err" 2>&1; then
	for n in $N_LIST; do add_skip "$n" 30 "$label" "build failed: $(head -c 120 "$W/build.err" | tr '\n' ' ')"; done
	exit 0
fi
for n in $N_LIST; do
	bytes=$(wc -c < "$IN/toy-$n.txt")
	got=$(best_of "$RUNS" "$W/toy" "$IN/toy-$n.txt") || { add_skip "$n" 30 "$label" "run failed"; continue; }
	add_row "$n" 30 "$label" "$bytes" "$got"
done
