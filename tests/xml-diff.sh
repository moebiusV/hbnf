#!/bin/sh
# XML against expat (tests/xml/oracle.py): the parser hbnf makes from corpus/xml/xml.hbnf and Python's
# xml.parsers.expat (plus the lexical rule of Namespaces in XML, that a name has at most one colon and
# that the parts are NCNames) are asked about the same texts.
# (1) Random well-formed documents must all be accepted.  (2) Random mutations of them -- a character
# deleted, inserted, replaced, swapped, doubled, the text cut -- must get the same answer, except where
# expat refuses for a check the grammar leaves out by design (a repeated attribute, a character
# reference to a character XML does not allow, an entity that is not declared, an encoding it does not
# know ...: the oracle marks those L).  An L document may be accepted; if it is refused it is not known
# whether the grammar or expat is right and it is counted apart.  (3) Every code point as the first and as
# a later character of a name, against the Fifth Edition's ranges (not against expat, whose tables are the
# Fourth Edition's).  (4) The folders corpus/xml/tests/{good,bad,loose}.
#   HBNF=/path/to/hbnf sh tests/xml-diff.sh [N [SEED]]      (HBNF_FLAGS= adds generator flags)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
N=${1:-3000}; SEED=${2:-1}
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
"$CLI" corpus/xml/xml.hbnf --backend=c ${HBNF_FLAGS:-} > "$W/j.c" 2> "$W/err" \
    || { echo "xml-diff: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/j.c")
cp "$W/j.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
/* files named on the command line, "FILE 1|0" for each; with -z, the documents on the standard
   input, separated by NUL, and one 1 or 0 for each on the standard output */
static int one(const char *buf) {
    char err[512];
    size_t line, col;
    $root out;
    return parse_text(buf, &out, err, sizeof err, &line, &col) ? 1 : 0;
}
int main(int argc, char **argv) {
    int i;
    if (argc == 2 && !strcmp(argv[1], "-z")) {
        size_t cap = 1 << 20, len = 0, n, at = 0;
        char *buf = malloc(cap);
        while ((n = fread(buf + len, 1, cap - len, stdin)) > 0) {
            len += n;
            if (len == cap) buf = realloc(buf, cap *= 2);
        }
        while (at < len) {
            putchar('0' + one(buf + at));
            at += strlen(buf + at) + 1;
        }
        putchar('\n');
        return 0;
    }
    for (i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        char *buf;
        long len;
        if (!f) return 2;
        fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
        buf = malloc(len + 1);
        if (fread(buf, 1, len, f) != (size_t)len) return 2;
        buf[len] = 0; fclose(f);
        printf("%s %d\n", argv[i], one(buf));
        free(buf);
    }
    return 0;
}
EOC
cc -std=gnu11 -D_GNU_SOURCE -O1 -w -Iruntime -o "$W/j" "$W/m.c" 2> "$W/cc" \
    || { echo "xml-diff: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
python3 -I tests/xml/oracle.py gen "$N" "$SEED" "$W/g" || exit 1
python3 -I tests/xml/oracle.py mut "$N" "$SEED" "$W/m" || exit 1
ls "$W"/g/*.xml | xargs "$W/j" > "$W/g.out"
ls "$W"/m/*.xml | xargs "$W/j" > "$W/m.out"
gbad=$(grep -c ' 0$' "$W/g.out")
agree=0; loose=0; strict=0; design=0; unknown=0
: > "$W/diff"
while read f v; do
    r=$(cat "${f%.xml}.ref")
    if [ "$r" = L ]; then
        if [ "$v" = 1 ]; then design=$((design+1)); else unknown=$((unknown+1)); fi
    elif [ "$r" = "$v" ]; then agree=$((agree+1))
    elif [ "$v" = 1 ]; then loose=$((loose+1)); echo "hbnf accepts, expat refuses: $f" >> "$W/diff"
    else strict=$((strict+1)); echo "hbnf refuses, expat accepts: $f" >> "$W/diff"; fi
done < "$W/m.out"
# every code point as the first character of a name and as a later one
python3 -I tests/xml/oracle.py names "$W/n" || exit 1
"$W/j" -z < "$W/n/names.in" | tr -d '\n' > "$W/n/names.out"
ncp=$(wc -c < "$W/n/names.ref")
nbad=$(cmp -l "$W/n/names.ref" "$W/n/names.out" | wc -l)
# the hand-written folders
bad_folder=0
for f in corpus/xml/tests/good/*.xml corpus/xml/tests/loose/*.xml; do
    "$W/j" "$f" | grep -q ' 1$' || { echo "FAIL good folder: $f"; bad_folder=1; }
done
for f in corpus/xml/tests/bad/*.xml; do
    "$W/j" "$f" | grep -q ' 0$' || { echo "FAIL bad folder: $f"; bad_folder=1; }
done
# and the oracle agrees with where each is filed: good accepted, bad refused, loose refused for a check left out
ls corpus/xml/tests/good/*.xml | xargs python3 -I tests/xml/oracle.py check | grep -v ' 1$' | sed 's/^/FAIL oracle refuses good: /' > "$W/folder"
ls corpus/xml/tests/bad/*.xml | xargs python3 -I tests/xml/oracle.py check | grep -v ' 0$' | sed 's/^/FAIL oracle accepts bad: /' >> "$W/folder"
ls corpus/xml/tests/loose/*.xml | xargs python3 -I tests/xml/oracle.py check | grep -v ' [L1]$' | sed 's/^/FAIL oracle refuses loose for its syntax: /' >> "$W/folder"
[ ! -s "$W/folder" ] || { cat "$W/folder"; bad_folder=1; }
echo "xml-diff: well-formed documents: $N, hbnf refuses $gbad"
echo "xml-diff: mutations: $agree agree, $loose hbnf looser, $strict hbnf stricter, $design accepted where expat refuses a check left out, $unknown refused where expat refuses a check left out (not known)"
echo "xml-diff: name characters: $((ncp / 2)) code points, $nbad differ from the Fifth Edition's ranges"
[ "$loose$strict" = 00 ] || head -10 "$W/diff"
[ -z "${DIFF_DIR:-}" ] || echo "xml-diff: files in $W"
[ "$gbad" = 0 ] && [ "$loose$strict" = 00 ] && [ "$nbad" = 0 ] && [ $bad_folder = 0 ] || exit 1
echo "xml-diff: OK"
