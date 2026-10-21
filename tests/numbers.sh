#!/bin/sh
# A number is a number: every place that takes one reads decimal, 0x hex, 0b binary and 0o octal alike
# (enum values, the bit a field starts at, widths, constants).
#   HBNF=/path/to/hbnf sh tests/numbers.sh      (default ./hbnf)
set -u
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
CC=${CC:-gcc}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0

"$CLI" tests/numbers/enum.hbnf --backend=c > "$T/enum.c" 2> "$T/err" || { echo "FAIL enum generation: $(cat "$T/err")"; exit 1; }
"$CLI" tests/numbers/bits.hbnf --backend=c > "$T/bits.c" 2> "$T/err" || { echo "FAIL bits generation: $(cat "$T/err")"; exit 1; }
cat > "$T/e.c" <<'M'
#include <stdio.h>
#include "enum.c"
int main(void) {
	struct { const char *text; int want; } t[] = { { "dec", 40 }, { "hex", 31 }, { "bin", 5 }, { "oct", 8 }, { "next", 9 } };
	int bad = 0;
	for (unsigned i = 0; i < sizeof t / sizeof t[0]; i++) {
		doc_t out; char err[128]; size_t line, col;
		char in[32]; snprintf(in, sizeof in, "%s 1", t[i].text);
		if (!parse_text(in, &out, err, sizeof err, &line, &col) || (int)out.n != t[i].want) {
			printf("FAIL %s: %d, wanted %d\n", t[i].text, (int)out.n, t[i].want);
			bad++;
		}
	}
	printf(bad ? "FAIL enum\n" : "PASS enum\n");
	return bad != 0;
}
M
cat > "$T/b.c" <<'M'
#include <stdio.h>
#include "bits.c"
int main(void) {
	/* hi = 0b100 = 4 bits, lo at bit 4 for 4 bits, the constant 0xF0, oct = 3 bits, pad = 5 */
	static const unsigned char in[] = { 0xA5, 0xF0, 0xBF };
	rec_t out; char err[128]; size_t at;
	if (!parse_bytes(in, sizeof in, &out, err, sizeof err, &at)) { printf("FAIL bits: %s\n", err); return 1; }
	if (out.hi != 0xA || out.lo != 0x5 || out.oct != 5 || out.pad != 0x1F) {
		printf("FAIL bits: hi=%x lo=%x oct=%x pad=%x\n", out.hi, out.lo, out.oct, out.pad); return 1; }
	printf("PASS bits\n");
	return 0;
}
M
rc=0
for x in e b; do
	$CC -Wall -I"$T" -o "$T/$x" "$T/$x.c" 2> "$T/cc" || { echo "FAIL $x: cc"; cat "$T/cc"; rc=1; continue; }
	"$T/$x" || rc=1
done
exit $rc
