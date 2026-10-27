#!/bin/sh
# The C79 grammar (corpus/c/c79.hbnf) against the UNIX/32V source tree, the C its own compiler
# was written in and compiled.  Fetches the Bell-32V tag of dspinellis/unix-history-repo into DIR
# (default ./c79-corpus), preprocesses every .c file with gcc's traditional preprocessor and the
# 32V headers alone (-nostdinc), and gives the result to the generated parser.  Every file is
# one the 32V compiler took, so each must be accepted.  Files that include a header the build
# generates (yacc's y.tab.h, eqn's e.def, as's as.yh) cannot be preprocessed and are counted apart.
#   HBNF=/path/to/hbnf sh scripts/c79-scan.sh [DIR]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
DIR=${1:-c79-corpus}
mkdir -p "$DIR"; DIR=$(cd "$DIR" && pwd)
[ -d "$DIR/src" ] || git clone -q --depth 1 --branch Bell-32V https://github.com/dspinellis/unix-history-repo.git "$DIR/src" 2> /dev/null \
	|| { echo "could not fetch the Bell-32V tag"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
"$CLI" corpus/c/c79.hbnf --backend=c > "$W/c79.c" 2> /dev/null || { echo "generate failed"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c79.c")
cat "$W/c79.c" corpus/c/check.c > "$W/m.c"
cc -O1 -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" -Itests/bsdinc "$W/m.c" -o "$W/check" || exit 1
S=$DIR/src; mkdir -p "$W/inc"; ln -s "$S/usr/src/sys/h" "$W/inc/sys"
M=$S/usr/src/cmd/pcc
n=0; skipped=0
find "$S" -name '*.c' | sort | while read -r f; do
	n=$((n + 1)); d=$(dirname "$f")
	if gcc -E -P -traditional-cpp -nostdinc -DTARGET=VAX -DFAMILY=SCJ -DHERE=VAX -DOUTPUT=BINARY -DPOLISH=POSTFIX \
		-I"$d" -I"$d/.." -I"$W/inc" -I"$M" -I"$S/usr/src/cmd/mip" -I"$S/usr/include" -I"$S/usr/src/sys/h" \
		"$f" > "$W/u$n.i" 2> /dev/null
	then echo "$W/u$n.i ${f#"$S"/usr/src/}"; else echo "- ${f#"$S"/usr/src/}"; fi
done > "$W/list.txt"
grep -c '^-' "$W/list.txt" | sed 's/^/files that need a generated header: /'
grep -v '^-' "$W/list.txt" > "$W/ok.txt"
"$W/check" $(cut -d' ' -f1 "$W/ok.txt") > "$W/out.txt" 2>&1
awk '/^ok/{o++} /^bad/{b++} END{printf "32V sources preprocessed: %d; the grammar accepts %d, refuses %d\n", o + b, o + 0, b + 0}' "$W/out.txt"
awk '/^bad/' "$W/out.txt" | head -5 | cut -c1-200
