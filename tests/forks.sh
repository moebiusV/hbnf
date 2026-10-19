#!/bin/sh
# Local forks (RFCPLAN.md decision 14): with --forks a later failure in a sequence
# retries the next alternative of the rule before it.  Without --forks the grammar is
# refused (its  "x" "y"  can never match after  "x" ); the output is tests/forks/expected.txt.
#   HBNF=/path/to/hbnf sh tests/forks.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
# without --forks the shadowed alternative is an error
if "$CLI" tests/forks/forks.hbnf --backend=c > /dev/null 2> "$W/err"; then
	echo "forks: FAIL (accepted without --forks)"; exit 1
fi
grep -q "can never match" "$W/err" || { echo "forks: FAIL (no shadowing message)"; exit 1; }
"$CLI" tests/forks/forks.hbnf --backend=c --forks --quiet-forks > "$W/f.c" 2> "$W/err" \
    || { echo "forks: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/f.c")
cat "$W/f.c" tests/forks/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE "-DROOT=$root" -Wall -Wno-unused-function -Werror -o "$W/f" "$W/m.c" 2> "$W/cc" \
    || { echo "forks: FAIL (compile)"; head -8 "$W/cc"; exit 1; }
"$W/f" > "$W/got.txt"
[ -z "${FORKS_UPDATE:-}" ] || cp "$W/got.txt" tests/forks/expected.txt
if ! cmp -s "$W/got.txt" tests/forks/expected.txt; then
	echo "forks: FAIL"; diff -u tests/forks/expected.txt "$W/got.txt" | head -30; exit 1
fi
# the forks are listed on stderr unless --quiet-forks
"$CLI" tests/forks/forks.hbnf --backend=c --forks 2>&1 >/dev/null | grep -q "fork: rule" \
    || { echo "forks: FAIL (no list of forks)"; exit 1; }
echo "forks: OK (a later failure retries the next alternative)"
