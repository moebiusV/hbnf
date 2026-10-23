#!/bin/sh
# Compare the C11 grammar with gcc on every .c file under the directories named: each is
# preprocessed (gcc -E -P, with its own directory and its parent as include paths), kept if gcc
# -fsyntax-only accepts the result, and given to the generated parser.  Prints how many the grammar
# accepts and the first few it refuses.  The preprocessor is gcc's: hbnf has no C preprocessor.
#   HBNF=/path/to/hbnf sh scripts/c-scan.sh DIR...
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
D=corpus/c
"$CLI" $D/c11.hbnf --backend=c > "$W/c11.c" 2> /dev/null || { echo "generate failed"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c11.c")
cat "$W/c11.c" $D/check.c > "$W/m.c"
cc -O1 -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || exit 1
n=0
find "$@" -name '*.c' -size -300k | sort | while read -r f; do
	n=$((n + 1)); d=$(dirname "$f")
	gcc -E -P -std=gnu11 -D_GNU_SOURCE -I"$d" -I"$d/.." -w "$f" > "$W/u$n.i" 2> /dev/null || continue
	gcc -fsyntax-only -std=gnu11 -w "$W/u$n.i" 2> /dev/null && echo "$W/u$n.i $f"
done > "$W/list.txt"
"$W/check" $(cut -d' ' -f1 "$W/list.txt") > "$W/out.txt" 2>&1
awk '/^ok/{o++} /^bad/{b++} END{printf "gcc accepts %d translation units; the grammar accepts %d, refuses %d\n", o + b, o + 0, b + 0}' "$W/out.txt"
awk '/^bad/' "$W/out.txt" | head -5 | cut -c1-200
