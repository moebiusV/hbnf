#!/bin/sh
# HTML (corpus/html/html.hbnf) against html5lib's strict parser (tests/html/oracle.py), which raises on a
# document that does not conform to the WHATWG HTML Living Standard.  (1) The files of corpus/html/tests,
# in three folders by what the two are expected to say: good (both accept), bad (both refuse) and oracle-stricter
# (the grammar accepts, html5lib refuses: it checks what a syntax cannot, or is older than the standard).
# (An end tag in another case than its start tag, <DIV>x</div>, is in good: `$tag` ignores case with the file.)
# (2) N random valid documents (every omissible end tag, raw text, svg and math, character references,
# every form of attribute) must all be accepted by both.  (3) N mutations of them -- a character deleted,
# inserted, replaced, swapped, doubled, the text cut -- must get the same answer from both, except where
# html5lib refuses a document for what it means (a duplicate attribute, a reference name that is not in the
# table, an element where the content model does not allow it): those are counted apart.  Without a python
# that has html5lib (PYTHON=), only the folders are run, against the verdicts their names give.
#   HBNF=/path/to/hbnf PYTHON=/path/to/python-with-html5lib sh tests/html-diff.sh [N [SEED]]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
PYTHON=${PYTHON:-python3}
N=${1:-1500}; SEED=${2:-1}
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
"$CLI" "${HTML_GRAMMAR:-corpus/html/html.hbnf}" --backend=c ${HBNF_FLAGS:-} > "$W/j.c" 2> "$W/err" \
    || { echo "html-diff: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
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
    || { echo "html-diff: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
T=corpus/html/tests
fail=0

# (1) the folders: the grammar's verdict by the folder, and html5lib's where it can be asked
oracle=1
$PYTHON -c 'import html5lib' 2> /dev/null || { oracle=0; echo "html-diff: no python with html5lib (set PYTHON): the oracle is not asked"; }
for d in good bad oracle-stricter; do
    case $d in good|oracle-stricter) wantg=1 ;; *) wantg=0 ;; esac
    case $d in good) wanto=1 ;; *) wanto=0 ;; esac
    ls "$T/$d"/*.html | xargs "$W/j" > "$W/$d.g"
    bad=$(grep -vc " $wantg\$" "$W/$d.g")
    [ "$bad" = 0 ] || { echo "html-diff: FAIL ($d: the grammar should say $wantg of:)"; grep -v " $wantg\$" "$W/$d.g" | head -5; fail=1; }
    if [ $oracle = 1 ]; then
        ls "$T/$d"/*.html | xargs $PYTHON -I tests/html/oracle.py check > "$W/$d.o"
        # a refusal for what the document means (2) counts as a refusal here
        awk -v w=$wanto '{ v = ($2 == 1) ? 1 : 0; if (v != w) print }' "$W/$d.o" > "$W/$d.od"
        [ ! -s "$W/$d.od" ] || { echo "html-diff: FAIL ($d: html5lib should say $wanto of:)"; head -5 "$W/$d.od"; fail=1; }
    fi
done
nfiles=$(ls $T/*/*.html | wc -l)

# (2) and (3) random documents and their mutations
if [ $oracle = 1 ]; then
    $PYTHON -I tests/html/oracle.py gen "$N" "$SEED" "$W/g" || exit 1
    $PYTHON -I tests/html/oracle.py mut "$N" "$SEED" "$W/m" || exit 1
    ls "$W"/g/*.html | xargs "$W/j" > "$W/g.out"
    ls "$W"/m/*.html | xargs "$W/j" > "$W/m.out"
    ls "$W"/g/*.html | xargs $PYTHON -I tests/html/oracle.py check > "$W/g.ref"
    gbad=$(grep -c ' 0$' "$W/g.out"); gref=$(grep -vc ' 1$' "$W/g.ref")
    agree=0; loose=0; strict=0; meaning=0; mboth=0
    : > "$W/diff"
    while read f v; do
        r=$(cat "${f%.html}.ref")
        if [ "$r" = "$v" ]; then agree=$((agree+1))
        elif [ "$r" = 2 ]; then
            meaning=$((meaning+1)); [ "$v" = 1 ] || mboth=$((mboth+1))
        elif [ "$v" = 1 ]; then loose=$((loose+1)); echo "grammar accepts, html5lib refuses: $f" >> "$W/diff"
        else strict=$((strict+1)); echo "grammar refuses, html5lib accepts: $f" >> "$W/diff"; fi
    done < "$W/m.out"
    echo "html-diff: $nfiles files in four folders; valid documents: $N, grammar refuses $gbad, html5lib refuses $gref"
    echo "html-diff: mutations: $agree agree, $meaning html5lib refuses for what they mean (either answer is fine), $loose grammar looser, $strict grammar stricter"
    [ "$loose$strict" = 00 ] || head -10 "$W/diff"
    [ "$gbad" = 0 ] && [ "$gref" = 0 ] && [ "$loose$strict" = 00 ] || fail=1
else
    echo "html-diff: $nfiles files in four folders (the grammar only)"
fi
[ -z "${DIFF_DIR:-}" ] || echo "html-diff: files in $W"
[ $fail = 0 ] || exit 1
echo "html-diff: OK"
