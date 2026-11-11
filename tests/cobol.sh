#!/bin/sh
# COBOL (corpus/cobol/cobol.hbnf, free format, and corpus/cobol/cobol-fixed.hbnf, the fixed reference format), C backend: the generated parser must accept every file in
# corpus/cobol/tests/good and refuse every file in corpus/cobol/tests/bad, and where GnuCOBOL is installed it
# must agree (cobc -free -fsyntax-only is the reference: every good file is accepted by it and every bad
# one refused).  The reserved words are generated from GnuCOBOL's cobc/reserved.c (tools/cobol_reserved.py);
# this checks that the file in the tree is what the generator makes, when bench/cache/cobol has the source.
#   HBNF=/path/to/hbnf sh tests/cobol.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=corpus/cobol

"$CLI" $D/cobol.hbnf --backend=c > "$W/cobol.c" 2> "$W/err" || { echo "cobol: FAIL (generate)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/cobol.c")
cat "$W/cobol.c" corpus/c/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/m.c" -o "$W/check" || { echo "cobol: FAIL (cc)"; exit 1; }

fail=0; n=0; ref=0
for kind in good bad; do
	for f in $D/tests/$kind/*.cob; do
		n=$((n + 1))
		got=$("$W/check" "$f" | cut -d' ' -f1)
		want=ok; [ $kind = bad ] && want=bad
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: $kind file, the parser says $got"; "$W/check" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
		if command -v cobc > /dev/null 2>&1; then
			ref=1
			cobc -free -fsyntax-only "$f" > /dev/null 2>&1; r=$?
			if { [ $kind = good ] && [ $r -ne 0 ]; } || { [ $kind = bad ] && [ $r -eq 0 ]; }; then
				echo "FAIL $f: cobc -free -fsyntax-only disagrees with the file's directory (rc $r)"; fail=$((fail + 1))
			fi
		fi
	done
done
# the fixed reference format: the same, with cobol-fixed.hbnf (the columns, `where (col ...)`) over corpus/cobol/tests/fixed/{good,bad}, and cobc -fixed
"$CLI" $D/cobol-fixed.hbnf --root=compilation-group --backend=c > "$W/fixed.c" 2> "$W/err" || { echo "cobol: FAIL (generate the fixed format)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/fixed.c")
cat "$W/fixed.c" corpus/c/check.c > "$W/mf.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/mf.c" -o "$W/checkf" || { echo "cobol: FAIL (cc, fixed format)"; exit 1; }
nf=0
for kind in good bad; do
	for f in $D/tests/fixed/$kind/*.cob; do
		n=$((n + 1)); nf=$((nf + 1))
		got=$("$W/checkf" "$f" | cut -d' ' -f1)
		want=ok; [ $kind = bad ] && want=bad
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: fixed format, $kind file, the parser says $got"; "$W/checkf" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
		if command -v cobc > /dev/null 2>&1; then
			ref=1
			cobc -fixed -fsyntax-only "$f" > /dev/null 2>&1; r=$?
			if { [ $kind = good ] && [ $r -ne 0 ]; } || { [ $kind = bad ] && [ $r -eq 0 ]; }; then
				echo "FAIL $f: cobc -fixed -fsyntax-only disagrees with the file's directory (rc $r)"; fail=$((fail + 1))
			fi
		fi
	done
done
if [ -f bench/cache/cobol/src/cobc/reserved.c ]; then
	python3 tools/cobol_reserved.py bench/cache/cobol/src/cobc/reserved.c | cmp -s - $D/reserved.hbnf \
		|| { echo "FAIL $D/reserved.hbnf is not what tools/cobol_reserved.py makes"; fail=$((fail + 1)); }
fi
[ $fail = 0 ] && echo "cobol: OK ($n files, $nf of them in the fixed format: the good accepted, the bad refused$( [ $ref = 1 ] && echo ', and cobc agrees'))" || { echo "cobol: $fail FAIL"; exit 1; }
