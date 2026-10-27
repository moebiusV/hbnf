#!/bin/sh
# The C79 grammar (corpus/c/c79.hbnf, the C of UNIX/32V's compiler), C backend: the generated
# parser must accept every file in corpus/c/tests79/good and refuse every file in
# corpus/c/tests79/bad.  The good files are in the dialect of usr/src/cmd/mip/cgram.y; each bad one
# is a construct that grammar has no production for (a prototype, `void`, `const`, a unary plus,
# a `//` comment, two strings side by side, a declaration after a statement).  scripts/c79-scan.sh
# runs the grammar over the 32V source tree itself.
#   HBNF=/path/to/hbnf sh tests/c79.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=corpus/c

"$CLI" $D/c79.hbnf --backend=c > "$W/c79.c" 2> "$W/err" || { echo "c79: FAIL (generate)"; grep -v warning "$W/err" | head -5; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c79.c")
cat "$W/c79.c" $D/check.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || { echo "c79: FAIL (cc)"; exit 1; }

fail=0; n=0
for kind in good bad; do
	for f in $D/tests79/$kind/*.c; do
		n=$((n + 1))
		got=$("$W/check" "$f" | cut -d' ' -f1)
		want=ok; [ $kind = bad ] && want=bad
		if [ "$got" != "$want" ]; then
			echo "FAIL $f: $kind file, the parser says $got"; "$W/check" "$f" | cut -c1-200; fail=$((fail + 1))
		fi
	done
done
if [ $fail -eq 0 ]; then echo "c79: OK ($n files: the good accepted, the bad refused)"; else echo "c79: FAIL ($fail of $n)"; exit 1; fi
