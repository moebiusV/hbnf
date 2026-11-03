#!/bin/sh
# The COBOL grammar against the programs of GnuCOBOL's own test suite (scripts/cobol-scan.sh): every program cobc
# accepts in free format that the parser refuses is a gap in the grammar (a program that uses COPY or REPLACE is
# set apart by the scan, as a preprocessor's work), and the number of them must not grow
# (tests/cobol/scan-baseline.txt is the number now; lower it when the grammar learns more).  The programs
# are fixed format in the suite and GPL: they are fetched, not kept (sh tools/cobol_fetch.sh), and converted
# to free format by tools/cobol_extract.py.  Skipped without the fetched source or without cobc.
#   HBNF=/path/to/hbnf sh tests/cobol-scan.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=bench/cache/cobol/tests/gnucobol-3.2/tests/testsuite.src
[ -d "$T" ] || { echo "cobol-scan: SKIP (no $T: sh tools/cobol_fetch.sh)"; exit 0; }
command -v cobc > /dev/null 2>&1 || { echo "cobol-scan: SKIP (no cobc)"; exit 0; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 tools/cobol_extract.py "$T" "$W/programs" > "$W/extract.txt" || { echo "cobol-scan: FAIL (extract)"; exit 1; }
HBNF="$CLI" sh scripts/cobol-scan.sh "$W/programs" "$W" > "$W/scan.txt" 2>&1 || { echo "cobol-scan: FAIL"; cat "$W/scan.txt" | head -5; exit 1; }
gaps=0; [ -f "$W/cobol-gaps.txt" ] && gaps=$(wc -l < "$W/cobol-gaps.txt")
total=$(sed -n 's/^cobol-scan: \([0-9]*\) programs.*/\1/p' "$W/scan.txt")
both=$(sed -n 's/^ *parser\/cobc ok\/ok: \([0-9]*\)/\1/p' "$W/scan.txt")
base=$(cat tests/cobol/scan-baseline.txt)
if [ "$gaps" -gt "$base" ]; then
	echo "cobol-scan: FAIL ($gaps programs cobc accepts and the parser refuses, up from $base):"
	head -10 "$W/cobol-gaps.txt"
	exit 1
fi
echo "cobol-scan: OK ($total programs; ${both:-0} accepted by both; $gaps gaps, baseline $base$( [ "$gaps" -lt "$base" ] && echo ', lower it'))"
