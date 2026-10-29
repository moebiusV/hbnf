#!/bin/sh
# runtime/hbnf_scalar.h, the conversions a reader of a tape needs: a number as an integer or a double, a string
# with its escapes undone.  (1) tests/scalar/scalar-test.c: ten million numbers and strings against strtod, bit
# for bit, and against a byte loop.  (2) corpus/json/json-tape-values.hbnf, which makes the conversions while
# it parses, on tests/scalar/values.json and on a generated document, against what Python's json says.
#   HBNF=/path/to/hbnf sh tests/scalar.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0
${CC:-cc} -std=gnu11 -O2 -Iruntime tests/scalar/scalar-test.c -o "$W/st" 2> "$W/cc.err" \
	|| { echo "scalar: FAIL (scalar-test.c does not compile: $(head -c 300 "$W/cc.err"))"; exit 1; }
"$W/st" > "$W/st.out" || { echo "scalar: FAIL ($(head -c 400 "$W/st.out"))"; fail=1; }
"$CLI" corpus/json/json-tape-values.hbnf --backend=c --root=json > "$W/v.c" 2> "$W/v.err" \
	|| { echo "scalar: FAIL (json-tape-values does not generate: $(head -c 300 "$W/v.err"))"; exit 1; }
cat "$W/v.c" tests/scalar/values-main.c > "$W/vm.c"
${CC:-cc} -std=gnu11 -O1 -w -D_GNU_SOURCE -Iruntime -include stdlib.h -DOUT_T=json_t "$W/vm.c" -o "$W/vbin" 2> "$W/cc.err" \
	|| { echo "scalar: FAIL (the values parser does not compile: $(head -c 300 "$W/cc.err"))"; exit 1; }
python3 bench/formats/gen.py json 60000 > "$W/gen.json"
for doc in tests/scalar/values.json "$W/gen.json"; do
	"$W/vbin" "$doc" > "$W/got.txt" 2>&1
	python3 tests/scalar/values-expect.py "$doc" > "$W/want.txt"
	cmp -s "$W/got.txt" "$W/want.txt" || { echo "scalar: FAIL (the tape of $doc differs from Python's reading: $(diff "$W/got.txt" "$W/want.txt" | head -4 | tr '\n' '|'))"; fail=1; }
done
[ $fail = 0 ] && echo "scalar: OK ($(sed 's/^scalar: OK (\(.*\))$/\1/' "$W/st.out"); the in-parse conversions agree with Python's json)"
exit $fail
