#!/bin/sh
# A rule that is only text except for a lookahead is read a character at a time, with a tree
# node for each piece, by the backends other than C; they say so.  C scans it as one token and
# draws no warning (tests/scanlook.sh).  The same rule without the lookahead is one token
# and draws no warning anywhere.
#   HBNF=/path/to/hbnf sh tests/textwarn.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
for b in rust zig ada; do
	"$CLI" tests/textwarn/lookahead.hbnf --backend=$b 2>&1 > /dev/null | grep -q '`line` is only text, but its lookahead' \
	    || { echo "textwarn: FAIL (no warning for a text rule with a lookahead, $b)"; exit 1; }
done
if "$CLI" tests/textwarn/lookahead.hbnf --backend=c 2>&1 > /dev/null | grep -q 'lookahead'; then
	echo "textwarn: FAIL (C warns about a text rule with a lookahead, which it scans)"; exit 1
fi
if "$CLI" tests/textwarn/plain.hbnf --backend=c 2>&1 > /dev/null | grep -q 'lookahead'; then
	echo "textwarn: FAIL (a warning for a rule without one)"; exit 1
fi
echo "textwarn: OK"
