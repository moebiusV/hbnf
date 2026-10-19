#!/bin/sh
# Mustache against chevron (tests/mustache/oracle.py): the parser hbnf makes from
# corpus/mustache/mustache.hbnf and chevron.render are asked about the same templates:
# random valid ones must all be accepted, and random mutations (a character deleted,
# inserted, replaced, swapped, doubled, the text cut) must get the same answer.
# hbnf may accept a template chevron refuses in one case only: a tag whose text holds a
# {{ ({{>a{{ }}), which mustache.js reads to the first }} as hbnf does and chevron does
# not; that is reported and allowed.  Anything else is a failure.
#   HBNF=... PYTHON=/path/to/python-with-chevron sh tests/mustache-diff.sh [N [SEED]]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
PYTHON=${PYTHON:-python3}
$PYTHON -c 'import chevron' 2>/dev/null || { echo "mustache-diff: SKIP (no python with chevron: set PYTHON)"; exit 0; }
N=${1:-3000}; SEED=${2:-1}
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
"$CLI" corpus/mustache/mustache.hbnf --backend=c > "$W/j.c" 2> "$W/err" \
    || { echo "mustache-diff: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/j.c")
cp "$W/j.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
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
cc -std=gnu11 -D_GNU_SOURCE -O1 -w -o "$W/j" "$W/m.c" 2> "$W/cc" \
    || { echo "mustache-diff: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
"$PYTHON" -I tests/mustache/oracle.py gen "$N" "$SEED" "$W/g" || exit 1
"$PYTHON" -I tests/mustache/oracle.py mut "$N" "$SEED" "$W/m" || exit 1
ls "$W"/g/*.mustache | xargs "$W/j" > "$W/g.out"
ls "$W"/m/*.mustache | xargs "$W/j" > "$W/m.out"
gbad=$(grep -c ' 0$' "$W/g.out")
agree=0; loose=0; strict=0
: > "$W/diff"
while read f v; do
    r=$(cat "${f%.mustache}.ref")
    if [ "$r" = "$v" ]; then agree=$((agree+1))
    elif [ "$v" = 1 ]; then loose=$((loose+1)); echo "hbnf accepts, python refuses: $f" >> "$W/diff"
    else strict=$((strict+1)); echo "hbnf refuses, python accepts: $f" >> "$W/diff"; fi
done < "$W/m.out"
# the hand-written folders
bad_folder=0
for f in corpus/mustache/tests/good/*.mustache; do
    "$W/j" "$f" | grep -q ' 1$' || { echo "FAIL good folder: $f"; bad_folder=1; }
done
for f in corpus/mustache/tests/bad/*.mustache; do
    "$W/j" "$f" | grep -q ' 0$' || { echo "FAIL bad folder: $f"; bad_folder=1; }
done
echo "mustache-diff: valid documents: $N, hbnf refuses $gbad"
echo "mustache-diff: mutations: $agree agree, $loose hbnf looser, $strict hbnf stricter"
[ "$loose$strict" = 00 ] || head -10 "$W/diff"
[ -z "${DIFF_DIR:-}" ] || echo "mustache-diff: files in $W"
others=$(grep '^hbnf accepts' "$W/diff" | cut -d: -f2 | while read f; do grep -q '{{[^}]*{{' "$f" || echo "$f"; done | wc -l)
[ "$gbad" = 0 ] && [ "$strict" = 0 ] && [ "$others" = 0 ] && [ $bad_folder = 0 ] || exit 1
echo "mustache-diff: OK"
echo "mustache-diff: OK"
