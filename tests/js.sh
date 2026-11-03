#!/bin/sh
# JavaScript (corpus/js/js.hbnf, ECMAScript 2023): the hand-written cases of corpus/js/tests/{good,bad} through every
# backend, as a Script, and corpus/js/tests/module-{good,bad} as a Module (--root=module).  Each bad file says in its
# first line, a comment, what is wrong with it.  tests/js-diff.sh asks V8 about random programs and mutations of them,
# and the test262 parser tests are tests/js262.sh.
#   HBNF=/path/to/hbnf sh tests/js.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${JS_BACKENDS:-c ada rust zig}"
. tests/suite.sh
# The Rust backend writes `let mut cp_tag = 0usize` for a back-reference and assigns it again before it is read; this
# grammar has none, but a generated parser may still warn of an unused assignment.
rustc() { command rustc -A unused-assignments "$@"; }
ACCEPT=$(ls corpus/js/tests/good/*.js)
REJECT=$(ls corpus/js/tests/bad/*.js)
suite js corpus/js/js.hbnf
ACCEPT=$(ls corpus/js/tests/module-good/*.js)
REJECT=$(ls corpus/js/tests/module-bad/*.js)
suite "js module" corpus/js/js.hbnf module
[ $rc = 0 ] && echo "js: OK" || { echo "js: FAIL"; exit 1; }
