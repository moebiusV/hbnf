#!/bin/sh
# Writes HBNF_Template_Syntax, the reader of the Mustache templates the code generators are written in: the Ada
# parser hbnf makes of grammars/template.hbnf, kept in the source tree because hbnf is built with it (hbnf
# cannot be built before it has been built).  Run it again after a change to the grammar, and with a hbnf built
# from the old reader if the generator changed in a way that matters to it; tests/template.sh checks that
# the files in the tree are what the grammar makes.
#   HBNF=/path/to/hbnf sh scripts/gen-template-syntax.sh [DIR]      (default ./hbnf; DIR default .)
set -eu
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
OUT=${1:-.}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" grammars/template.hbnf --backend=ada --package=HBNF_Template_Syntax > "$W/all.ada"
(cd "$W" && gnatchop -w all.ada > /dev/null)
for f in hbnf_template_syntax.ads hbnf_template_syntax-parser.ads hbnf_template_syntax-parser.adb; do
	cp "$W/$f" "$OUT/$f"
done
