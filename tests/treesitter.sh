#!/bin/sh
# The tree-sitter backend (--backend=tree-sitter): the grammar.js it writes for a
# grammar is run through the real tree-sitter generator, which names the choices it
# cannot decide one at a time ("Add a conflict for these rules: `a`, `b`"); this loop
# adds each to --ts-conflicts and tries again.  Then the programs the hbnf parser
# accepts must parse with no ERROR in tree-sitter, and the ones it refuses must
# not.  Needs `node` and `tree-sitter` (the CLI): set TS_NODE_DIR (a node's bin
# directory) and TS_CLI (the tree-sitter binary), else the test is skipped.
#   HBNF=/path/to/hbnf TS_NODE_DIR=... TS_CLI=... sh tests/treesitter.sh GRAMMAR.hbnf GOOD_DIR BAD_DIR
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
GRAMMAR=${1:-corpus/algol60/algol60.hbnf}
GOOD=${2:-corpus/algol60/tests/good}
BAD=${3:-corpus/algol60/tests/bad}
if [ -z "${TS_CLI:-}" ] || [ -z "${TS_NODE_DIR:-}" ]; then
	echo "treesitter: SKIP (no TS_CLI / TS_NODE_DIR: a tree-sitter binary and a node)"; exit 0
fi
export PATH="$TS_NODE_DIR:$PATH"
W=$(mktemp -d)
[ -n "${TS_KEEP:-}" ] || trap 'rm -rf "$W"' EXIT
TSDIR=${TS_DIR:-$W/ts}
conf=$(sh tests/ts-build.sh "$GRAMMAR" "$TSDIR") || { echo "treesitter: FAIL"; exit 1; }
n=$(echo "${conf#conflicts: }" | tr ';' '\n' | grep -c .)
bad=0; ok=0; no=0
for f in "$GOOD"/*; do
	( cd "$TSDIR" && "$TS_CLI" parse "$OLDPWD/$f" ) > "$W/out" 2>&1
	if grep -q "ERROR\|MISSING" "$W/out"; then echo "FAIL good (tree-sitter errors): $f"; bad=1; else ok=$((ok+1)); fi
done
for f in "$BAD"/*; do
	( cd "$TSDIR" && "$TS_CLI" parse "$OLDPWD/$f" ) > "$W/out" 2>&1
	if grep -q "ERROR\|MISSING" "$W/out"; then no=$((no+1)); else echo "NOTE bad parses in tree-sitter: $f"; fi
done
[ $bad = 0 ] || exit 1
echo "treesitter: OK ($n conflicts declared: ${conf#conflicts: }; $ok programs parse, $no of the refused ones show errors)"
