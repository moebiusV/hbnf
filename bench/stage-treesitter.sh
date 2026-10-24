#!/bin/sh
# stage-treesitter.sh — the toy as a tree-sitter grammar (compare/grammar.js):
# a cold parse, and a re-parse after a one-byte edit with the old tree.
. "$here/lib.sh"
BUDGET=7   # four measurements of this tool: about 30 s
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rm -f "$RESULTS"/rows/*/4[0-9]-*.md
cp "$here/compare/grammar.js" "$W/"
if ! (cd "$W" && tree-sitter generate \
	&& gcc -O2 -std=gnu11 -w -I/opt/tree-sitter/include -I/opt/tree-sitter/src -Isrc -I"$here/drv" \
	   "$here/drv/ts_toy.c" src/parser.c /opt/tree-sitter/src/lib.c -o ts_toy) > "$W/build.err" 2>&1; then
	for n in $N_LIST; do
		add_skip "$n" 40 "tree-sitter" "build failed: $(tail -c 160 "$W/build.err" | tr '\n' ' ')"
		add_skip "$n" 41 "tree-sitter, re-parse after a one-byte edit" "build failed"
	done
	exit 0
fi
for n in $N_LIST; do
	bytes=$(wc -c < "$IN/toy-$n.txt")
	got=$(best_of "$RUNS" "$W/ts_toy" "$IN/toy-$n.txt") || { add_skip "$n" 40 "tree-sitter" "run failed"; continue; }
	add_row "$n" 40 "tree-sitter $TS_VERSION" "$bytes" "$got"
	got=$(best_of "$RUNS" "$W/ts_toy" "$IN/toy-$n.txt" edit) || { add_skip "$n" 41 "tree-sitter, re-parse after a one-byte edit" "run failed"; continue; }
	add_edit_row "$n" 41 "tree-sitter $TS_VERSION, re-parse after a one-byte edit" "$got"
done
