#!/bin/sh
# CSS (corpus/css/css.hbnf): the hand-written cases of corpus/css/tests through every backend, once for each root:
#   stylesheet        good/*.css and bad/*.css       (the content of an HTML <style> element)
#   declaration-list  declarations/{good,bad}/*.decl (the value of a style attribute)
#   selector-list     selectors/{good,bad}/*.sel     (what querySelector takes)
# Each bad file says in its first line, a comment, what is wrong with it.  tests/css-diff.sh asks tinycss2 and
# soupsieve about the same files, the css-parsing-tests, and random sheets.
#   HBNF=/path/to/hbnf sh tests/css.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${CSS_BACKENDS:-c ada rust zig}"
. tests/suite.sh
C=corpus/css/tests
ACCEPT=$(ls $C/good/*.css);                REJECT=$(ls $C/bad/*.css);                suite "css stylesheet" corpus/css/css.hbnf stylesheet
ACCEPT=$(ls $C/declarations/good/*.decl);  REJECT=$(ls $C/declarations/bad/*.decl);  suite "css declaration-list" corpus/css/css.hbnf declaration-list
ACCEPT=$(ls $C/selectors/good/*.sel);      REJECT=$(ls $C/selectors/bad/*.sel);      suite "css selector-list" corpus/css/css.hbnf selector-list
# The same stylesheets read onto a tape (--layout=tape, C): the verdicts of the tree.  The generated C did not
# compile for this grammar (CONTEXTS section 26, item 43: the white-space rule `ws`, named in a rule that writes).
if command -v cc > /dev/null 2>&1; then
	d=$W/csstape; mkdir -p "$d"
	"$CLI" corpus/css/css.hbnf --backend=c --layout=tape --root=stylesheet > "$d/p.c" 2> "$d/err" \
		|| { echo "css: FAIL (tape: does not generate: $(head -c 200 "$d/err"))"; rc=1; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$d/p.c")
	cat "$d/p.c" corpus/c/check.c > "$d/m.c"
	if cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$d/m.c" -o "$d/m" 2> "$d/cc.txt"; then
		"$d/m" $C/good/*.css > "$d/good.out" 2>&1 \
			|| { echo "css: FAIL (tape refuses a good stylesheet: $(grep -a '^bad' "$d/good.out" | head -2))"; rc=1; }
		for f in $C/bad/*.css; do
			"$d/m" "$f" > /dev/null 2>&1 && { echo "css: FAIL (tape accepts $f)"; rc=1; }
		done
	else
		echo "css: FAIL (tape: the C does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; rc=1
	fi
fi
[ $rc = 0 ] && echo "css: OK" || { echo "css: FAIL"; exit 1; }
