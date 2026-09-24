#!/bin/sh
# Macros expand to what a hand-expanded config says: pfctl's parser, with the
# generated deep compare (--compare), finds tests/compare/macros.conf and
# expanded.conf equal rule by rule, and different.conf not.
#   HBNF_CLI=/path/to/hbnf_cli sh tests/compare.sh     (default ./hbnf_cli)
set -u
cd "$(dirname "$0")/.."
CLI=${HBNF_CLI:-./hbnf_cli}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" grammars/pfctl.hbnf --backend=c --compare > "$W/pf.c" || { echo "compare: FAIL (generate)"; exit 1; }
cat "$W/pf.c" tests/compare/main.c > "$W/cmp.c"
cc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$W/cmp.c" -o "$W/cmp" || { echo "compare: FAIL (compile)"; exit 1; }
if ! out=$("$W/cmp" tests/compare/macros.conf tests/compare/expanded.conf); then
	echo "compare: FAIL (macros.conf vs expanded.conf: $out)"; exit 1
fi
if "$W/cmp" tests/compare/expanded.conf tests/compare/different.conf >/dev/null; then
	echo "compare: FAIL (different.conf compared equal)"; exit 1
fi
echo "compare: OK ($out; different.conf differs)"
