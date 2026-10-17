#!/bin/sh
# stage-yacc.sh — the toy as flex + byacc and flex + bison, the way parse.y
# files are written (compare/toy.l, compare/toy.y).
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rm -f "$RESULTS"/rows/*/2[0-9]-*.md

build() {   # build TAG YACC-COMMAND
	tag=$1; shift
	d=$W/$tag; mkdir -p "$d"
	cp "$here/compare/toy.l" "$here/compare/toy.y" "$d/"
	(cd "$d" && "$@" && flex -o lex.yy.c toy.l \
		&& gcc -O2 -std=gnu11 -w -I. -I"$here/drv" y.tab.c lex.yy.c -o toy) > "$d/build.err" 2>&1
}

order=20
for spec in "byacc|byacc + flex|byacc -d -o y.tab.c toy.y" "bison|bison + flex|bison -y -d -o y.tab.c toy.y"; do
	tag=${spec%%|*}; rest=${spec#*|}; label=${rest%%|*}; cmd=${rest#*|}
	if ! build "$tag" $cmd; then
		for n in $N_LIST; do add_skip "$n" $order "$label" "build failed: $(head -c 120 "$W/$tag/build.err" | tr '\n' ' ')"; done
		order=$((order + 1)); continue
	fi
	for n in $N_LIST; do
		bytes=$(wc -c < "$IN/toy-$n.txt")
		got=$(best_of "$RUNS" "$W/$tag/toy" "$IN/toy-$n.txt") || { add_skip "$n" $order "$label" "run failed"; continue; }
		add_row "$n" $order "$label" "$bytes" "$got"
	done
	order=$((order + 1))
done
