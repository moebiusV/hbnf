#!/bin/sh
# Compare a C grammar with gcc on every .c file under the directories named: each is
# preprocessed (gcc -E -P, with its own directory and its parent as include paths), kept if gcc
# -fsyntax-only accepts the result, and given to the generated parser.  Prints how many the grammar
# accepts and the first few it refuses.  The preprocessor is gcc's: hbnf has no C preprocessor.
#   HBNF=/path/to/hbnf sh scripts/c-scan.sh DIR...                      the C11 grammar, gcc -std=gnu11
#   GRAMMAR=c89 STD=c89 sh scripts/c-scan.sh DIR...                      the C90 grammar, gcc -std=c89 -pedantic-errors
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
if [ -n "${KEEP:-}" ]; then W=$KEEP; mkdir -p "$W"; else W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fi   # KEEP=dir keeps the preprocessed files
D=corpus/c
G=${GRAMMAR:-c11}; STD=${STD:-gnu11}
PED=; GNU=
case $STD in
c89|c99) PED=-pedantic-errors
	# the system headers spell some standard things the GNU way; a strict grammar reads the standard's
	GNU="-D__extension__= -D__restrict=restrict -D__restrict__=restrict -D__inline=inline -D__inline__=inline -D__const=const -D__signed__=signed -D__volatile__=volatile -D__builtin_va_list=void*"
	;;
esac
"$CLI" $D/$G.hbnf --backend=c > "$W/$G.c" 2> /dev/null || { echo "generate failed"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$G.c")
cat "$W/$G.c" $D/check.c > "$W/m.c"
cc -O1 -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || exit 1
n=0
find "$@" -name '*.c' -size -300k | sort | while read -r f; do
	n=$((n + 1)); d=$(dirname "$f")
	gcc -E -P -std=$STD $GNU "-D__attribute__(x)=" "-D__asm__(x)=" "-D__asm(x)=" -I"$d" -I"$d/.." -w "$f" > "$W/u$n.i" 2> /dev/null || continue
	gcc -fsyntax-only -std=$STD $PED "$W/u$n.i" 2> /dev/null && echo "$W/u$n.i $f"
done > "$W/list.txt"
"$W/check" $(cut -d' ' -f1 "$W/list.txt") > "$W/out.txt" 2>&1
awk '/^ok/{o++} /^bad/{b++} END{printf "gcc accepts %d translation units; the grammar accepts %d, refuses %d\n", o + b, o + 0, b + 0}' "$W/out.txt"
awk '/^bad/' "$W/out.txt" | head -5 | cut -c1-200
