#!/bin/sh
# The COBOL grammar against the programs of GnuCOBOL's own test suite (scripts/cobol-scan.sh): every program cobc
# accepts in free format that the parser refuses is a gap in the grammar (a program that uses COPY or REPLACE is
# set apart by the scan, as a preprocessor's work), and the number of them must not grow
# (tests/cobol/scan-baseline.txt is the number now; lower it when the grammar learns more).  The NIST COBOL-85 suite, which
# tools/cobol_fetch.sh also fetches, is scanned the same way against tests/cobol/nist-baseline.txt.  The programs
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

# scan NAME DIR BASELINE: the gaps of one corpus against its baseline; prints a summary, returns 1 when the gaps grew
scan() {
	mkdir -p "$W/$1"
	HBNF="$CLI" sh scripts/cobol-scan.sh "$2" "$W/$1" > "$W/$1/scan.txt" 2>&1 || { echo "cobol-scan: FAIL ($1)"; head -5 "$W/$1/scan.txt"; return 1; }
	gaps=0; [ -f "$W/$1/cobol-gaps.txt" ] && gaps=$(wc -l < "$W/$1/cobol-gaps.txt")
	total=$(sed -n 's/^cobol-scan: \([0-9]*\) programs.*/\1/p' "$W/$1/scan.txt")
	both=$(sed -n 's/^ *parser\/cobc ok\/ok: \([0-9]*\)/\1/p' "$W/$1/scan.txt")
	base=$(cat "$3")
	if [ "$gaps" -gt "$base" ]; then
		echo "cobol-scan: FAIL ($1: $gaps programs cobc accepts and the parser refuses, up from $base):"
		head -10 "$W/$1/cobol-gaps.txt"
		return 1
	fi
	SUMMARY="$SUMMARY${SUMMARY:+; }$1: $total programs, ${both:-0} accepted by both, $gaps gaps, baseline $base$( [ "$gaps" -lt "$base" ] && echo ', lower it')"
	return 0
}

SUMMARY=""
python3 tools/cobol_extract.py "$T" "$W/programs" > "$W/extract.txt" || { echo "cobol-scan: FAIL (extract)"; exit 1; }
scan gnucobol "$W/programs" tests/cobol/scan-baseline.txt || exit 1
# the NIST suite, when tools/cobol_fetch.sh has fetched it
if [ -d bench/cache/cobol/nist ]; then
	scan nist bench/cache/cobol/nist tests/cobol/nist-baseline.txt || exit 1
fi
echo "cobol-scan: OK ($SUMMARY)"
