#!/bin/sh
# TOML 1.0 against Python's tomllib (tests/toml/oracle.py): the parser hbnf makes from
# corpus/toml/toml.hbnf and tomllib are asked about the same texts.  (1) Random valid
# documents must all be accepted.  (2) Random mutations of them -- a character deleted,
# inserted, replaced, swapped, doubled, the text cut -- must get the same answer from both,
# except where tomllib refuses a text for what it means (a key or a table defined twice):
# those are counted apart, because a grammar of the syntax cannot see them.  The folders
# corpus/toml/tests/{good,bad} are checked too.
#   HBNF=/path/to/hbnf sh tests/toml-diff.sh [N [SEED]]
#   TOML_GRAMMAR=corpus/toml/toml-tape.hbnf asks it of another grammar for the same language
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
N=${1:-3000}; SEED=${2:-1}
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
"$CLI" "${TOML_GRAMMAR:-corpus/toml/toml.hbnf}" --backend=c ${HBNF_FLAGS:-} > "$W/j.c" 2> "$W/err" \
    || { echo "toml-diff: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
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
cc -std=gnu11 -D_GNU_SOURCE -O1 -w -Iruntime -o "$W/j" "$W/m.c" 2> "$W/cc" \
    || { echo "toml-diff: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
python3 -I tests/toml/oracle.py gen "$N" "$SEED" "$W/g" || exit 1
python3 -I tests/toml/oracle.py mut "$N" "$SEED" "$W/m" || exit 1
ls "$W"/g/*.toml | xargs "$W/j" > "$W/g.out"
ls "$W"/m/*.toml | xargs "$W/j" > "$W/m.out"
gbad=$(grep -c ' 0$' "$W/g.out")
agree=0; loose=0; strict=0; meaning=0
: > "$W/diff"
while read f v; do
    r=$(cat "${f%.toml}.ref")
    if [ "$r" = "$v" ]; then agree=$((agree+1))
    elif [ "$r" = 2 ]; then meaning=$((meaning+1))
    elif [ "$v" = 1 ]; then loose=$((loose+1)); echo "hbnf accepts, python refuses: $f" >> "$W/diff"
    else strict=$((strict+1)); echo "hbnf refuses, python accepts: $f" >> "$W/diff"; fi
done < "$W/m.out"
bad_folder=0
for f in corpus/toml/tests/good/*.toml; do
    "$W/j" "$f" | grep -q ' 1$' || { echo "FAIL good folder: $f"; bad_folder=1; }
done
for f in corpus/toml/tests/bad/*.toml; do
    "$W/j" "$f" | grep -q ' 0$' || { echo "FAIL bad folder: $f"; bad_folder=1; }
done
echo "toml-diff: valid documents: $N, hbnf refuses $gbad"
echo "toml-diff: mutations: $agree agree, $meaning tomllib refuses for what they mean (either answer is fine), $loose hbnf looser, $strict hbnf stricter"
[ "$loose$strict" = 00 ] || head -10 "$W/diff"
[ -z "${DIFF_DIR:-}" ] || echo "toml-diff: files in $W"
[ "$gbad" = 0 ] && [ "$loose$strict" = 00 ] && [ $bad_folder = 0 ] || exit 1
echo "toml-diff: OK"
