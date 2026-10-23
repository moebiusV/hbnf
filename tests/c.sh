#!/bin/sh
# The C11 grammar (corpus/c/c11.hbnf), C backend: the generated parser must accept every file in
# corpus/c/tests/good and refuse every file in corpus/c/tests/bad, and where gcc is installed it
# must agree (gcc -fsyntax-only is the reference).  scripts/c-scan.sh runs the same comparison over
# any directory of C sources, preprocessed.  The grammar uses the typedef context, which only the C
# backend has so far.
#   HBNF=/path/to/hbnf sh tests/c.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=corpus/c

"$CLI" $D/c11.hbnf --backend=c > "$W/c11.c" 2> "$W/err" || { echo "c: FAIL (generate)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c11.c")
cat "$W/c11.c" $D/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || { echo "c: FAIL (cc)"; exit 1; }

fail=0; n=0
for kind in good bad; do
	for f in $D/tests/$kind/*.c; do
		n=$((n + 1))
		got=$("$W/check" "$f" | cut -d' ' -f1)
		want=ok; [ $kind = bad ] && want=bad
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: $kind file, the parser says $got"; "$W/check" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
		if command -v gcc > /dev/null 2>&1; then
			gcc -fsyntax-only -std=gnu11 -w "$f" > /dev/null 2>&1; r=$?
			if { [ $kind = good ] && [ $r -ne 0 ]; } || { [ $kind = bad ] && [ $r -eq 0 ]; }; then
				echo "NOTE $f: gcc -fsyntax-only disagrees with the file's directory (rc $r)"
			fi
		fi
	done
done
[ $fail = 0 ] && echo "c: OK ($n files: the good accepted, the bad refused)" || { echo "c: $fail FAIL"; exit 1; }
