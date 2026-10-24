#!/bin/sh
# YAML (corpus/yaml/yaml.hbnf): the cases of corpus/yaml/tests/{good,bad}.  The grammar has
# parameters that are numbers worked out while parsing, which only the C backend emits so far.
# tests/yaml-suite.sh runs the YAML test suite and tests/yaml-diff.sh compares with PyYAML.
#   HBNF=/path/to/hbnf sh tests/yaml.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${YAML_BACKENDS:-c}"
. tests/suite.sh
ACCEPT=$(ls corpus/yaml/tests/good/*.yaml)
REJECT=$(ls corpus/yaml/tests/bad/*.yaml)
suite yaml corpus/yaml/yaml.hbnf yaml
[ $rc = 0 ] && echo "yaml: OK" || { echo "yaml: FAIL"; exit 1; }
