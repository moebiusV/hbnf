#!/bin/sh
# Runs the COBOL grammar (corpus/cobol/cobol.hbnf) and GnuCOBOL's cobc over a directory of free-format COBOL programs
# and says where they differ: the files cobc accepts and the parser refuses (the gaps in the grammar), and the files
# cobc refuses and the parser accepts (a checking pass's business, mostly: an undefined name is no syntax error).
# Programs that use COPY or REPLACE are listed apart (cobol-outofscope.txt), not as gaps.
# tools/cobol_extract.py makes such a directory from GnuCOBOL's test suite (bench/cache/cobol, from
# tools/cobol_fetch.sh).  With no cobc, only the parser's verdicts are written.
#   HBNF=/path/to/hbnf sh scripts/cobol-scan.sh DIR [OUT]      (default ./hbnf; OUT is where the lists go, default /tmp)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
DIR=${1:?usage: cobol-scan.sh DIR [OUT]}
OUT=${2:-/tmp}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" corpus/cobol/cobol.hbnf --backend=c > "$W/cobol.c" 2> "$W/err" || { echo "cobol-scan: generate failed"; head -5 "$W/err"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/cobol.c")
cat "$W/cobol.c" corpus/c/check.c > "$W/m.c"
cc -O1 -w -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$root" "$W/m.c" -o "$W/check" || { echo "cobol-scan: cc failed"; exit 1; }
ls "$DIR"/*.cob | sort > "$W/files"
xargs "$W/check" < "$W/files" > "$OUT/cobol-parser.txt" 2>&1
n=$(wc -l < "$W/files"); pa=$(grep -c '^ok ' "$OUT/cobol-parser.txt")
echo "cobol-scan: $n programs; the parser accepts $pa"
if command -v cobc > /dev/null 2>&1; then
	: > "$OUT/cobol-cobc.txt"
	while read -r f; do
		if cobc -free -fsyntax-only "$f" > "$W/cobc.out" 2>&1; then echo "ok $f"; else echo "bad $f: $(grep -m1 'error' "$W/cobc.out" | sed 's/^[^:]*:[0-9]*: //')"; fi
	done < "$W/files" >> "$OUT/cobol-cobc.txt"
	ca=$(grep -c '^ok ' "$OUT/cobol-cobc.txt")
	echo "cobol-scan: cobc accepts $ca"
	awk '{print $1, $2}' "$OUT/cobol-parser.txt" | sed 's/:$//' | sort -k2 > "$W/p"
	awk '{print $1, $2}' "$OUT/cobol-cobc.txt" | sed 's/:$//' | sort -k2 > "$W/c"
	join -j 2 "$W/p" "$W/c" | awk '{ k = $2 "/" $3; n[k]++; if ($2 == "bad" && $3 == "ok") print $1 > "'"$OUT"'/cobol-gaps.txt"; if ($2 == "ok" && $3 == "bad") print $1 > "'"$OUT"'/cobol-lenient.txt" } END { for (k in n) print "   parser/cobc " k ": " n[k] }' | sort
	# a program with COPY or REPLACE (a preprocessor's work, RFCPLAN) is not a gap of the grammar
	if [ -f "$OUT/cobol-gaps.txt" ]; then
		: > "$W/in"; : > "$OUT/cobol-outofscope.txt"
		while read -r f; do
			if grep -qiE '^[[:space:]]*(copy|replace)[[:space:]]' "$f"; then echo "$f" >> "$OUT/cobol-outofscope.txt"; else echo "$f" >> "$W/in"; fi
		done < "$OUT/cobol-gaps.txt"
		cp "$W/in" "$OUT/cobol-gaps.txt"
		echo "cobol-scan: $(wc -l < "$OUT/cobol-gaps.txt") gaps in the grammar; $(wc -l < "$OUT/cobol-outofscope.txt") more need COPY or REPLACE"
	fi
fi
