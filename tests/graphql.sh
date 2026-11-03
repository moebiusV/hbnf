#!/bin/sh
# GraphQL (corpus/graphql/graphql.hbnf, the October 2021 specification): the hand-written cases of
# corpus/graphql/tests/{good,bad} through every backend.  Each bad file says in its first line, a comment,
# what is wrong with it.  No GraphQL library is installed here to ask, so the files are the oracle.
#   HBNF=/path/to/hbnf sh tests/graphql.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${GRAPHQL_BACKENDS:-c ada rust zig}"
. tests/suite.sh
ACCEPT=$(ls corpus/graphql/tests/good/*.graphql)
REJECT=$(ls corpus/graphql/tests/bad/*.graphql)
suite graphql corpus/graphql/graphql.hbnf
[ $rc = 0 ] && echo "graphql: OK" || { echo "graphql: FAIL"; exit 1; }
