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
[ $rc = 0 ] && echo "css: OK" || { echo "css: FAIL"; exit 1; }
