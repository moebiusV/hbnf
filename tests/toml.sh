#!/bin/sh
# TOML (corpus/toml/toml.hbnf): the hand-written cases of corpus/toml/tests/{good,bad}
# through every backend.  tests/toml-diff.sh checks the C parser against Python's tomllib.
#   HBNF=/path/to/hbnf sh tests/toml.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${TOML_BACKENDS:-c ada rust zig}"
. tests/suite.sh
ACCEPT=$(ls corpus/toml/tests/good/*.toml)
REJECT=$(ls corpus/toml/tests/bad/*.toml)
suite toml corpus/toml/toml.hbnf
[ $rc = 0 ] && echo "toml: OK" || { echo "toml: FAIL"; exit 1; }
