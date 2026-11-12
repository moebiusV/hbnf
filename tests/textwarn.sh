#!/bin/sh
# A rule that is only text except for a lookahead is scanned as one token, with no warning, by the C, Rust, Zig and Ada backends
# (tests/scanlook.sh).  One whose alternatives overlap cannot be scanned: it is read a character at a time, a tree node for
# each piece, and every backend says so.  The same rule without the lookahead is one token and draws no warning anywhere.
#   HBNF=/path/to/hbnf sh tests/textwarn.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
for b in c rust zig ada; do
	if "$CLI" tests/textwarn/lookahead.hbnf --backend=$b --package=Tw 2>&1 > /dev/null | grep -q 'lookahead'; then
		echo "textwarn: FAIL ($b warns about a text rule with a lookahead, which it scans)"; exit 1
	fi
	"$CLI" tests/scanlook/overlap.hbnf --backend=$b --package=Tw 2>&1 > /dev/null | grep -q 'only text, but its lookahead' \
	    || { echo "textwarn: FAIL (no warning for a text rule with a lookahead that cannot be scanned, $b)"; exit 1; }
	if "$CLI" tests/textwarn/plain.hbnf --backend=$b --package=Tw 2>&1 > /dev/null | grep -q 'lookahead'; then
		echo "textwarn: FAIL (a warning for a rule without one, $b)"; exit 1
	fi
done
echo "textwarn: OK"
