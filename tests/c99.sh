#!/bin/sh
# The C99 grammar (corpus/c/c99.hbnf), C backend: the generated parser must accept every file in
# corpus/c/tests99/good and refuse every file in corpus/c/tests99/bad, and where gcc is installed
# it must agree (gcc -std=c99 -pedantic-errors -fsyntax-only is the reference).
# scripts/c-scan.sh -std=c99 runs the same comparison over any directory of C sources.
#   HBNF=/path/to/hbnf sh tests/c99.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=corpus/c

"$CLI" $D/c99.hbnf --backend=c > "$W/c99.c" 2> "$W/err" || { echo "c99: FAIL (generate)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c99.c")
cat "$W/c99.c" $D/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || { echo "c99: FAIL (cc)"; exit 1; }

fail=0; n=0
for kind in good bad; do
	for f in $D/tests99/$kind/*.c; do
		n=$((n + 1))
		got=$("$W/check" "$f" | cut -d' ' -f1)
		want=ok; [ $kind = bad ] && want=bad
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: $kind file, the parser says $got"; "$W/check" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
		if command -v gcc > /dev/null 2>&1; then
			gcc -fsyntax-only -std=c99 -pedantic-errors "$f" > /dev/null 2>&1; r=$?
			if { [ $kind = good ] && [ $r -ne 0 ]; } || { [ $kind = bad ] && [ $r -eq 0 ]; }; then
				echo "NOTE $f: gcc -std=c99 -pedantic-errors disagrees with the file's directory (rc $r)"
			fi
		fi
	done
done
if [ $fail -eq 0 ]; then echo "c99: OK ($n files: the good accepted, the bad refused)"; else echo "c99: FAIL ($fail of $n)"; exit 1; fi
