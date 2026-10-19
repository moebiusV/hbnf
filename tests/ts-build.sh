#!/bin/sh
# Make the tree-sitter parser of a grammar in a directory: grammar.js from
# `hbnf --backend=tree-sitter --ts-ordered`, then `tree-sitter generate`, adding the
# conflicts it names (one at a time) with --ts-conflicts until it succeeds.
#   HBNF=... TS_NODE_DIR=... TS_CLI=... sh tests/ts-build.sh GRAMMAR.hbnf OUTDIR
# Prints the conflicts declared on the last line, as   conflicts: a,b;c,d
set -u
CLI=${HBNF:-./hbnf}
GRAMMAR=$1
OUT=$2
export PATH="$TS_NODE_DIR:$PATH"
mkdir -p "$OUT/src"
rm -f "$OUT/src/scanner.c"
conf=""
n=0
while :; do
	"$CLI" "$GRAMMAR" --backend=tree-sitter --ts-ordered --ts-scanner="$OUT/src/scanner.c" ${conf:+--ts-conflicts="$conf"} \
	    > "$OUT/grammar.js" 2> "$OUT/err" || { echo "ts-build: hbnf failed: $(head -c 300 "$OUT/err")" >&2; exit 1; }
	( cd "$OUT" && "$TS_CLI" generate ) > "$OUT/gen" 2>&1 && break
	pair=$(sed -n 's/.*Add a conflict for these rules: *//p' "$OUT/gen" | head -1 | sed 's/`//g; s/ //g')
	if [ -z "$pair" ]; then echo "ts-build: generate failed" >&2; sed 's/\x1b\[[0-9;]*m//g' "$OUT/gen" | head -20 >&2; exit 1; fi
	conf="${conf:+$conf;}$pair"
	n=$((n+1))
	[ $n -lt 80 ] || { echo "ts-build: more than 80 conflicts" >&2; exit 1; }
done
echo "conflicts: $conf"
