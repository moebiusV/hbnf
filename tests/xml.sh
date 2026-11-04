#!/bin/sh
# XML (corpus/xml/xml.hbnf): the hand-written cases of corpus/xml/tests/{good,bad,loose} through the C backend.
# The grammar keeps the attribute names of a tag and the declared entities in `context` sets, and checks that no
# entity recurs with a `%where { }` in C: so far only the C backend has that (Rust and Zig have contexts but not
# code, Ada has neither, tree-sitter leaves them out).  bad holds the documents the specification's
# well-formedness constraints refuse (a repeated attribute, a character reference to a character XML does not
# allow, an entity that is not declared, one that recurs, an external or unparsed entity where it may not be);
# loose holds the one check the grammar still leaves out, the balance of an entity's markup: accepted.
# tests/xml-diff.sh checks the C parser against expat.
#   HBNF=/path/to/hbnf sh tests/xml.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${XML_BACKENDS:-c}"
. tests/suite.sh
# The Rust backend writes `let mut cp_tag = 0usize` for a back-reference (`as`) and assigns it again before
# it is read, which rustc warns of (unused_assignments) and suite.sh's `-D warnings` makes an error: allowed
# here, until the generator stops writing it.
rustc() { command rustc -A unused-assignments "$@"; }
ACCEPT=$(ls corpus/xml/tests/good/*.xml corpus/xml/tests/loose/*.xml)
REJECT=$(ls corpus/xml/tests/bad/*.xml)
suite xml corpus/xml/xml.hbnf
[ $rc = 0 ] && echo "xml: OK" || { echo "xml: FAIL"; exit 1; }
