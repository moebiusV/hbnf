#!/bin/sh
# HTML (corpus/html/html.hbnf): the hand-written cases of corpus/html/tests through every backend.  The
# grammar takes a case as the folder says (good and oracle-stricter: accepted; bad and grammar-stricter:
# refused).  Then the variant with an island, corpus/html/html-islands.hbnf, where the inside of <script> is
# read by the grammar of js-stub.hbnf (`include "js-stub.hbnf" as js`): the cases of corpus/html/tests-islands
# are named for what each grammar says -- ok-* both accept; guest-refuses-* the island variant refuses what
# the plain grammar takes as raw text; guest-reads-past-end-* the island variant accepts a script that holds a
# string with "</script>" in it, which a browser (and the plain grammar) end at the first "</script".
# tests/html-diff.sh asks Python's html5lib about the same files and about random documents.
#   HBNF=/path/to/hbnf sh tests/html.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${HTML_BACKENDS:-c ada rust zig}"
# the code a back-reference makes in Rust assigns a value that is not read before it is set again: a lint, not a fault (tests/backref.sh builds it with -A warnings too)
RUST_LINTS="-A warnings"
. tests/suite.sh
P=corpus/html/tests
I=corpus/html/tests-islands
ACCEPT=$(ls $P/good/*.html $P/oracle-stricter/*.html)
REJECT=$(ls $P/bad/*.html $P/grammar-stricter/*.html)
suite html corpus/html/html.hbnf
ACCEPT=$(ls $I/ok-*.html $I/guest-refuses-*.html)
REJECT=$(ls $I/guest-reads-past-end-*.html)
suite "html (the cases of the islands)" corpus/html/html.hbnf
ACCEPT=$(ls $P/good/*.html $P/oracle-stricter/*.html $I/ok-*.html $I/guest-reads-past-end-*.html)
REJECT=$(ls $P/bad/*.html $P/grammar-stricter/*.html $I/guest-refuses-*.html)
suite "html islands" corpus/html/html-islands.hbnf
[ $rc = 0 ] && echo "html: OK" || { echo "html: FAIL"; exit 1; }
