#!/bin/sh
# Enum values (RFCPLAN.md step 7b): `"icmp"@1`, an enum literal with a number of
# its own, as in C.  The C values are checked by a program; the other three
# backends are checked in tests/schema.sh, which builds and runs them.
#   HBNF=/path/to/hbnf sh tests/enumval.sh      (default ./hbnf)
set -u
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
CC=${CC:-gcc}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0

"$CLI" tests/enumval/proto.hbnf --backend=c > "$T/proto.c" 2> "$T/err" \
	|| { echo "FAIL generation: $(cat "$T/err")"; exit 1; }
cat > "$T/main.c" <<'M'
#include <stdio.h>
#include "proto.c"
int main(void) {
	int bad = 0;
	struct { const char *text; int want; } t[] = {
		{ "icmp", 1 }, { "tcp", 6 }, { "udp", 17 }, { "ipv6-icmp", 58 },
		{ "sctp", 132 }, { "other", 133 } };
	for (unsigned i = 0; i < sizeof t / sizeof t[0]; i++) {
		doc_t out; char err[128]; size_t line, col;
		char in[64];
		snprintf(in, sizeof in, "%s 1", t[i].text);
		if (!parse_text(in, &out, err, sizeof err, &line, &col)
		    || (int)out.proto != t[i].want) {
			printf("FAIL %s: %d, wanted %d\n", t[i].text, (int)out.proto, t[i].want);
			bad++;
		}
	}
	if (PROTO_ICMP != 1 || PROTO_TCP != 6 || PROTO_UDP != 17
	    || PROTO_IPV6_ICMP != 58 || PROTO_SCTP != 132 || PROTO_OTHER != 133) {
		printf("FAIL the enumerators\n"); bad++;
	}
	if (!bad) printf("PASS the values of the enumerators and of what is read\n");
	return bad != 0;
}
M
$CC -Wall -Wextra -I"$T" -o "$T/main" "$T/main.c" 2> "$T/cc" \
	|| { echo "FAIL cc: $(head -c 400 "$T/cc")"; exit 1; }
"$T/main" || fail=$((fail+1))

# The other three spell the numbers too.
for b in rust zig ada; do
	"$CLI" tests/enumval/proto.hbnf --backend=$b > "$T/proto.$b" 2>&1
	case $b in
	rust) want='Proto_Sctp = 132' ;;
	zig)  want='sctp = 132' ;;
	ada)  want='Proto_Sctp => 132' ;;
	esac
	if grep -qF -- "$want" "$T/proto.$b"; then echo "PASS $b spells the numbers"
	else echo "FAIL $b: no '$want'"; fail=$((fail+1)); fi
done

# Refused, with a reason.
for pair in "dup:two literals have the value" \
            "notenum:only a rule whose alternatives are all plain literals"; do
	n=${pair%%:*}; want=${pair#*:}
	if "$CLI" tests/enumval/$n.hbnf --backend=c > /dev/null 2> "$T/err"; then
		echo "FAIL $n: accepted"; fail=$((fail+1))
	elif grep -qF -- "$want" "$T/err"; then echo "PASS $n refused"
	else echo "FAIL $n: $(cat "$T/err")"; fail=$((fail+1)); fi
done
[ "$fail" -eq 0 ] && echo "enumval OK" || { echo "enumval: $fail FAIL"; exit 1; }
