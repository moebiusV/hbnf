#!/bin/sh
# The ALGOL 60 pretty-printer (corpus/algol60/pp.c): every program in
# corpus/algol60/tests/good is printed, the output must parse, and printing that
# again must give the same text, plain and with --functional.  Each program in
# corpus/algol60/tests/pretty/ is printed in the three styles (plain, --functional,
# --clang) and compared with its .pretty, .functional and .clang files.
#   HBNF=/path/to/hbnf sh tests/algol60-pp.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" corpus/algol60/algol60.hbnf --backend=c --writer --ast > "$W/a60.c" 2> "$W/err" \
    || { echo "algol60-pp: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
cc -std=gnu11 -D_GNU_SOURCE -w -include "$W/a60.c" -o "$W/pp" corpus/algol60/pp.c 2> "$W/cc" \
    || { echo "algol60-pp: FAIL (compile)"; head -8 "$W/cc"; exit 1; }
fail=0; n=0
for f in corpus/algol60/tests/good/*.a60; do
	n=$((n+1))
	for flag in "" --functional; do
		"$W/pp" -c $flag "$f" 2> "$W/e" || { echo "FAIL $f $flag"; head -20 "$W/e"; fail=1; }
	done
done
# the same program in each of the three styles
for f in corpus/algol60/tests/pretty/*.a60; do
	for style in pretty functional clang; do
		flag=""; [ $style = pretty ] || flag="--$style"
		"$W/pp" $flag "$f" > "$W/got" 2> "$W/e" || { echo "FAIL $f $flag"; head -5 "$W/e"; fail=1; continue; }
		if [ -n "${PP_UPDATE:-}" ]; then cp "$W/got" "${f%.a60}.$style"; fi
		cmp -s "$W/got" "${f%.a60}.$style" || { echo "FAIL $f $flag"; diff -u "${f%.a60}.$style" "$W/got" | head -30; fail=1; }
	done
done
[ $fail = 0 ] || exit 1
echo "algol60-pp: OK ($n programs print and read back the same, plain and --functional; three styles compared)"
