#!/bin/sh
# Rules that declare a value (`name :: type = ...`), in the C backend: each grammar of tests/valued/ is
# generated, compiled with tests/valued/driver.c (root `top`), and run on the cases after it.
# Regressions of CONTEXTS.md section 26, items 65 to 68.
#   HBNF=/path/to/hbnf sh tests/valued.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
# run NAME: the cases on stdin, `input=wanted output` (the first line of the output)
run() {
	n=$1
	"$CLI" tests/valued/$n.hbnf --backend=c > "$W/$n.c" 2> "$W/$n.err" \
		|| { echo "valued: FAIL ($n: $(head -c 200 "$W/$n.err"))"; fail=1; cat > /dev/null; return; }
	cat tests/valued/driver.c >> "$W/$n.c"
	${CC:-cc} -std=gnu11 -w -o "$W/$n" "$W/$n.c" 2> "$W/cc.err" \
		|| { echo "valued: FAIL ($n: does not compile: $(head -c 300 "$W/cc.err"))"; fail=1; cat > /dev/null; return; }
	while IFS== read -r input want; do
		got=$("$W/$n" "$input")
		[ "$got" = "$want" ] || { echo "valued: FAIL ($n '$input': got '$got', wanted '$want')"; fail=1; }
	done
}
run charrep <<'CASES'
a=ok 0
a123=ok 0
b7=ok 0
b=error 1:2
c=ok 0
c5=ok 0
cc=error 1:2
x=error 1:1
CASES
run charneg <<'CASES'
[abc]=ok 0
[]=ok 0
[ab=error 1:4
{x}=ok 0
{}=error 1:2
{xy}=error 1:3
x=error 1:1
[a]b=error 1:4
CASES
[ $fail = 0 ] && echo "valued: ok"
exit $fail
