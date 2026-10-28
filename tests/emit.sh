#!/bin/sh
# The type after `::` and the `%emit` block (RFCPLAN.md step 15), as far as the reader goes:
# `name :: type = ...` is read for one word, several words and a parameterised rule; a head with no
# type, or no `=`, is refused with the form it wants; `%emit` is read between elements and at the
# end of a rule, and a grammar that uses it is refused by rule name until a backend generates it.
#   HBNF=/path/to/hbnf sh tests/emit.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
for f in plain typed; do
	"$CLI" tests/emit/$f.hbnf --backend=c > "$W/$f.c" 2> "$W/$f.err" \
		|| { echo "emit: FAIL ($f: $(head -c 200 "$W/$f.err"))"; fail=1; }
done
for f in no-type no-eq; do
	"$CLI" tests/emit/$f.hbnf --backend=c 2>&1 > /dev/null | grep -q 'expected `name :: type =`' \
		|| { echo "emit: FAIL ($f: not refused with the form it wants)"; fail=1; }
done
"$CLI" tests/emit/read.hbnf --backend=c 2>&1 > /dev/null | grep -q 'rule `object` has an %emit' \
	|| { echo "emit: FAIL (read: %emit is not read, or not refused by rule name)"; fail=1; }
[ $fail = 0 ] && echo "emit: OK (types read; %emit read and, for now, refused)"
exit $fail
