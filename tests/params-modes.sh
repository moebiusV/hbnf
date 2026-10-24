#!/bin/sh
# A rule whose parameters are numbers is made in a copy for each value (--expand-params) or run
# in a frame of them (--run-params); Auto, the default, picks.  The two must accept and refuse
# the same texts, in every backend.  The grammar is a table of seven precedence levels.
#   HBNF=/path/to/hbnf sh tests/params-modes.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
REAL=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${PARAMS_BACKENDS:-c ada rust zig}"
. tests/suite.sh
ACCEPT=$(ls tests/params-modes/good/*.txt)
REJECT=$(ls tests/params-modes/bad/*.txt)
for mode in expand run; do
	printf '#!/bin/sh\nexec %s --%s-params "$@"\n' "$(cd "$(dirname "$REAL")" && pwd)/$(basename "$REAL")" "$mode" > "$W/hbnf-$mode"
	chmod +x "$W/hbnf-$mode"
	CLI="$W/hbnf-$mode"
	suite "params-$mode" tests/params-modes/expr.hbnf expr
done
[ $rc = 0 ] && echo "params-modes: OK" || { echo "params-modes: FAIL"; exit 1; }
