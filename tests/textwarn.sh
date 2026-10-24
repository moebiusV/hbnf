#!/bin/sh
# A rule that is only text except for a lookahead is read a character at a time, with a tree
# node for each piece; the generator says so.  The same rule without the lookahead is one
# token and draws no warning.
#   HBNF=/path/to/hbnf sh tests/textwarn.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
"$CLI" tests/textwarn/lookahead.hbnf --backend=c 2>&1 > /dev/null | grep -q '`line` is only text, but its lookahead' \
    || { echo "textwarn: FAIL (no warning for a text rule with a lookahead)"; exit 1; }
if "$CLI" tests/textwarn/plain.hbnf --backend=c 2>&1 > /dev/null | grep -q 'lookahead'; then
	echo "textwarn: FAIL (a warning for a rule without one)"; exit 1
fi
echo "textwarn: OK"
