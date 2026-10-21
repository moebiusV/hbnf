#!/bin/sh
# Error messages: every thing that could have stood at the failure is named
# ("expected one of"), and a construct that takes more than a couple of lines says
# where it began (a 'BEGIN' with no 'END').  The output must be tests/errors/expected.txt.
#   HBNF=/path/to/hbnf sh tests/errors.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
run() { # grammar files...
	g=$1; shift
	"$CLI" "$g" --backend=c > "$W/p.c" || { echo "errors: FAIL (generate $g)"; exit 1; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
	sed "s/ROOT_T/$root/" tests/errors/main.c > "$W/main.c"
	cat "$W/p.c" "$W/main.c" > "$W/m.c"
	cc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$W/m.c" -o "$W/m" || { echo "errors: FAIL (compile $g)"; exit 1; }
	"$W/m" "$@"
}
{
	run corpus/algol60/algol60.hbnf tests/errors/no-end.a60 tests/errors/paren.a60
	run corpus/json/json.hbnf tests/errors/json-comma.json
} > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/errors/expected.txt; then
	echo "errors: FAIL"; diff -u tests/errors/expected.txt "$W/got.txt" | head -30; exit 1
fi
echo "errors: OK (one of ..., and where an unfinished construct began)"
