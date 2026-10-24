#!/bin/sh
# YAML against PyYAML (tests/yaml/oracle.py): the parser hbnf makes from corpus/yaml/yaml.hbnf
# and PyYAML are asked about the same texts.  (1) Random documents PyYAML wrote, in its block
# and flow styles at several widths and indents, must all be accepted.  (2) Random mutations of
# them are given to both, and the answers counted: PyYAML reads YAML 1.1 and the grammar 1.2, so
# a difference there is reported and not a failure.  The cases of the YAML test suite are
# checked by tests/yaml-suite.sh, which is the judge of what 1.2 says.
#   HBNF=/path/to/hbnf sh tests/yaml-diff.sh [N [SEED]]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
N=${1:-1000}; SEED=${2:-1}
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
"$CLI" corpus/yaml/yaml.hbnf --backend=c --root=yaml > "$W/y.c" 2> "$W/err" \
    || { echo "yaml-diff: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/y.c")
cp "$W/y.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
#include <stdio.h>
int main(int argc, char **argv) {
    int i;
    for (i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        char *buf, err[512];
        long len;
        size_t line, col;
        $root out;
        if (!f) return 2;
        fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
        buf = malloc(len + 1);
        if (fread(buf, 1, len, f) != (size_t)len) return 2;
        buf[len] = 0; fclose(f);
        printf("%s %d\n", argv[i], parse_text(buf, &out, err, sizeof err, &line, &col) ? 1 : 0);
        free(buf);
    }
    return 0;
}
EOC
cc -std=gnu11 -D_GNU_SOURCE -O1 -w -o "$W/y" "$W/m.c" 2> "$W/cc" \
    || { echo "yaml-diff: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
python3 -I tests/yaml/oracle.py gen "$N" "$SEED" "$W/g" || exit 1
python3 -I tests/yaml/oracle.py mut "$N" "$SEED" "$W/m" || exit 1
ls "$W"/g/*.yaml | xargs "$W/y" > "$W/g.out"
ls "$W"/m/*.yaml | xargs "$W/y" > "$W/m.out"
gbad=$(grep -c ' 0$' "$W/g.out")
agree=0; loose=0; strict=0
: > "$W/diff"
while read f v; do
    r=$(cat "${f%.yaml}.ref")
    if [ "$r" = "$v" ]; then agree=$((agree+1))
    elif [ "$v" = 1 ]; then loose=$((loose+1)); echo "hbnf accepts, PyYAML refuses: $f" >> "$W/diff"
    else strict=$((strict+1)); echo "hbnf refuses, PyYAML accepts: $f" >> "$W/diff"; fi
done < "$W/m.out"
echo "yaml-diff: documents PyYAML wrote: $N, hbnf refuses $gbad"
echo "yaml-diff: mutations: $agree agree, $loose hbnf looser, $strict hbnf stricter (YAML 1.2 against 1.1)"
[ -z "${DIFF_DIR:-}" ] || echo "yaml-diff: files in $W"
if [ "$gbad" != 0 ]; then
    grep ' 0$' "$W/g.out" | head -5
    exit 1
fi
echo "yaml-diff: OK"
