#!/bin/sh
# Parameterised rules (RFCPLAN.md; METACOMPILERS.md): a rule with parameters is a
# template, every use makes an ordinary rule when the grammar is read, a value outside
# a parameter's domain or a use that grows without end is an error then.
#   HBNF=/path/to/hbnf sh tests/params.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0
for f in tests/params/ok_*.hbnf; do
	n=$(basename "$f" .hbnf)
	if "$CLI" "$f" --backend=c > "$T/$n.c" 2> "$T/$n.err"; then
		echo "PASS $n"
	else
		echo "FAIL $n: $(head -c 300 "$T/$n.err")"; fail=$((fail+1))
	fi
done
# bad_NAME.hbnf: refused, with a message containing the first line of bad_NAME.want
for f in tests/params/bad_*.hbnf; do
	n=$(basename "$f" .hbnf)
	want=$(head -1 "tests/params/$n.want")
	if "$CLI" "$f" --backend=c > /dev/null 2> "$T/$n.err"; then
		echo "FAIL $n: accepted"; fail=$((fail+1))
	elif grep -qF -- "$want" "$T/$n.err"; then
		echo "PASS $n"
	else
		echo "FAIL $n: message was: $(head -c 400 "$T/$n.err")"; fail=$((fail+1))
	fi
done
[ $fail = 0 ] && echo "params OK" || { echo "params: $fail FAIL"; exit 1; }
