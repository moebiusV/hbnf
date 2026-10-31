#!/bin/sh
# HBNF_Template, the Mustache renderer the code generators use (it replaced the mustache-ada library):
#  - hbnf_template_syntax*.ad[sb] are what hbnf makes of grammars/template.hbnf (the reader of a template),
#    kept in the tree because hbnf is built with them; regenerating them must give the same files;
#  - tests/template/check.adb renders a table of templates against views and checks the text, including the
#    lines that hold only a section tag or a comment, and what is refused.
# Needs gnatmake (it is skipped without).
#   HBNF=/path/to/hbnf sh tests/template.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0
HBNF="$CLI" sh scripts/gen-template-syntax.sh "$W" 2> "$W/err" || { echo "template: FAIL (does not generate: $(head -c 300 "$W/err"))"; exit 1; }
for f in hbnf_template_syntax.ads hbnf_template_syntax-parser.ads hbnf_template_syntax-parser.adb; do
	cmp -s "$W/$f" "$f" || { echo "template: FAIL ($f is not what grammars/template.hbnf makes: sh scripts/gen-template-syntax.sh)"; fail=1; }
done
if command -v gnatmake > /dev/null 2>&1; then
	mkdir -p "$W/b"
	if (cd "$W/b" && gnatmake -q -gnat2022 -gnatws -I"$OLDPWD" -I"$OLDPWD/tests/template" check.adb -o check > cc.txt 2>&1); then
		out=$("$W/b/check" 2>&1) || { echo "template: FAIL"; echo "$out" | head -20; fail=1; }
		n=$(echo "$out" | sed -n 's/^ok  *\([0-9]*\) cases.*/\1/p')
	else echo "template: FAIL (check.adb does not compile: $(head -c 300 "$W/b/cc.txt"))"; fail=1; fi
else
	n=0; echo "template: (no gnatmake: only the generated files were checked)"
fi
[ $fail = 0 ] && echo "template: OK (the reader is what the grammar makes; ${n:-0} rendering cases)"
exit $fail
