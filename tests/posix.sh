#!/bin/sh
# The POSIX shell grammar (corpus/posix/shell.y): the generated C parser must accept every file
# in corpus/posix/tests/good and refuse every file in corpus/posix/tests/bad, and where dash is
# installed it must agree on each (dash -n is the reference).  The corpus is small and
# hand-written; scripts/posix-scan.sh runs the same comparison over every shell script on the
# machine and over mutations of them.
#   HBNF=/path/to/hbnf sh tests/posix.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=corpus/posix

"$CLI" $D/shell.y --backend=c > "$W/shell.c" 2> "$W/err" || { echo "posix: FAIL (generate)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/shell.c")
cat "$W/shell.c" $D/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w -DOUT_T="$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || { echo "posix: FAIL (cc)"; exit 1; }

fail=0; n=0
for kind in good bad; do
	for f in $D/tests/$kind/*.sh; do
		n=$((n + 1))
		got=$("$W/check" "$f" | cut -d' ' -f1)
		want=ok; [ $kind = bad ] && want=bad
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: $kind file, the parser says $got"; "$W/check" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
		if command -v dash > /dev/null 2>&1; then
			dash -n "$f" > /dev/null 2>&1; r=$?
			if { [ $kind = good ] && [ $r -ne 0 ]; } || { [ $kind = bad ] && [ $r -eq 0 ]; }; then
				echo "NOTE $f: dash -n disagrees with the file's directory (rc $r)"
			fi
		fi
	done
done
[ $fail = 0 ] && echo "posix: OK ($n files: the good accepted, the bad refused)" || { echo "posix: $fail FAIL"; exit 1; }
