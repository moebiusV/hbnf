#!/bin/sh
# ALGOL 60 against the Report: tests/algol60/reference.py reads the Report's BNF
# (corpus/algol60/syntax.txt) with an Earley recognizer that has nothing to do with
# hbnf.  (1) Random sentences of the Report must all be accepted by the parser hbnf
# makes from algol60.hbnf.  (2) Random mutations of them (a token deleted,
# doubled, swapped, inserted or replaced) are asked of both; where they differ the
# hbnf side is looser or stricter than the Report.  Stricter is a failure.  Looser
# is allowed and is, in every case seen (50,000 mutations), the one difference
# corpus/algol60/README.md names: expressions are not typed, so  NOT 7  and
# TRUE < TRUE  are accepted.  Prints the counts; exits 1 on a sentence the
# Report accepts and hbnf refuses, or on a mutation hbnf refuses and the Report
# accepts.
#   HBNF=/path/to/hbnf sh tests/algol60-diff.sh [N [SEED]]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
N=${1:-800}; SEED=${2:-1}
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
"$CLI" corpus/algol60/algol60.hbnf --backend=c ${HBNF_FLAGS:-} > "$W/a.c" 2> "$W/err" \
    || { echo "algol60-diff: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/a.c")
cp "$W/a.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
int main(int argc, char **argv) {
    int i;
    for (i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "r");
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
cc -std=gnu11 -D_GNU_SOURCE -O1 -w -o "$W/a60" "$W/m.c" 2> "$W/cc" \
    || { echo "algol60-diff: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
python3 -I tests/algol60/reference.py gen "$N" "$SEED" "$W/g" || exit 1
python3 -I tests/algol60/reference.py mut "$N" "$SEED" "$W/m" || exit 1
ls "$W"/g/*.a60 | xargs "$W/a60" > "$W/g.out"
ls "$W"/m/*.a60 | xargs "$W/a60" > "$W/m.out"
gref=$(wc -l < "$W/g.out"); gbad=$(grep -c ' 0$' "$W/g.out")
: > "$W/loose"; : > "$W/strict"; agree=0
while read f v; do
    r=$(cat "${f%.a60}.ref")
    if [ "$r" = "$v" ]; then agree=$((agree+1))
    elif [ "$v" = 1 ]; then echo "$f" >> "$W/loose"
    else echo "$f" >> "$W/strict"; fi
done < "$W/m.out"
echo "algol60-diff: Report sentences: $gref, hbnf refuses $gbad"
echo "algol60-diff: mutations: $agree agree, $(wc -l < "$W/loose") hbnf looser, $(wc -l < "$W/strict") hbnf stricter"
if [ -n "${DIFF_DIR:-}" ]; then echo "algol60-diff: files in $W"; fi
[ "$gbad" = 0 ] && [ ! -s "$W/strict" ] || exit 1
