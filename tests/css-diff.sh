#!/bin/sh
# CSS (corpus/css/css.hbnf) against the parsers that other people wrote (tests/css/oracle.py):
#   tinycss2    the structure of CSS Syntax 3: tokens, rules, declarations, nested rules (and its own tests,
#               Simon Sapin's css-parsing-tests, which are in corpus/css/tests/css-parsing-tests)
#   soupsieve   Selectors 4 (and the selectors of its own test suite, corpus/css/tests/selectors-soupsieve.txt)
# (1) css-parsing-tests: every case whose expected tree holds no error node must be accepted, and the ones that hold
#     one refused; the cases where the grammar differs (it is for conforming style sheets, CSS Syntax recovers) are
#     listed with the reason in corpus/css/tests/css-parsing-tests.expect and must be exactly those.
# (2) The selectors of soupsieve's test suite: the grammar's verdict on each is the one filed in the corpus.
# (3) N random conforming style sheets (every at-rule, value function and selector the grammar knows) must all be
#     accepted by both.  (4) N mutations of other random sheets -- a character deleted, inserted, replaced, swapped,
#     doubled, the text cut -- must get the same answer from both, except where soupsieve refuses for what a selector
#     means (an unknown pseudo-class, a pseudo-element): those are counted apart.
# (5) The folders of corpus/css/tests: the grammar agrees with the folder, and the oracle accepts what the grammar
#     accepts in good/.  Without a python that has tinycss2 and soupsieve (PYTHON=), only (1), (2), (5) and the
#     folders are run, against the verdicts the files and folders give.
#   HBNF=/path/to/hbnf PYTHON=/path/to/python-with-tinycss2-and-soupsieve sh tests/css-diff.sh [N [SEED]]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
PYTHON=${PYTHON:-python3}
N=${1:-1500}; SEED=${2:-1}
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
G=${CSS_GRAMMAR:-corpus/css/css.hbnf}
fail=0

# a parser for each root: FILE... gives "FILE 1|0"; -z reads documents separated by NUL on the standard input
build() { # ROOT
    "$CLI" "$G" --root="$1" --backend=c ${HBNF_FLAGS:-} > "$W/$1.c" 2> "$W/$1.err" \
        || { echo "css-diff: FAIL (generate $1: $(head -c 300 "$W/$1.err"))"; exit 1; }
    root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$1.c")
    cp "$W/$1.c" "$W/$1.m.c"
    cat >> "$W/$1.m.c" <<EOC
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
    cc -std=gnu11 -D_GNU_SOURCE -O1 -w -Iruntime -o "$W/$1" "$W/$1.m.c" 2> "$W/$1.cc" \
        || { echo "css-diff: FAIL (compile $1)"; head -5 "$W/$1.cc"; exit 1; }
}
build stylesheet; build declaration-list; build selector-list; build component-value-list

oracle=1
$PYTHON -c 'import tinycss2, soupsieve' 2> /dev/null || { oracle=0; echo "css-diff: no python with tinycss2 and soupsieve (set PYTHON): the oracles are not asked"; }

# (1) css-parsing-tests
T=corpus/css/tests
$PYTHON tests/css/oracle.py cpt $T/css-parsing-tests "$W/cpt" > "$W/cpt.jobs" || exit 1
while read name root; do
    "$W/$root" -z < "$W/cpt/$name.$root.in" > "$W/cpt/$name.$root.out"
done < "$W/cpt.jobs"
$PYTHON tests/css/oracle.py cpt-report "$W/cpt" $T/css-parsing-tests.expect || fail=1

# (2) soupsieve's own selectors
$PYTHON tests/css/oracle.py sel-cases $T/selectors-soupsieve.txt "$W/sel" || exit 1
"$W/selector-list" -z < "$W/sel.in" > "$W/sel.out"
$PYTHON tests/css/oracle.py sel-report $T/selectors-soupsieve.txt "$W/sel.out" || fail=1

# (5) the folders
nfiles=0
for f in $T/good/*.css; do nfiles=$((nfiles+1)); "$W/stylesheet" "$f" | grep -q ' 1$' || { echo "css-diff: FAIL good: $f"; fail=1; }; done
for f in $T/bad/*.css; do nfiles=$((nfiles+1)); "$W/stylesheet" "$f" | grep -q ' 0$' || { echo "css-diff: FAIL bad: $f"; fail=1; }; done
if [ $oracle = 1 ]; then
    ls $T/good/*.css | xargs $PYTHON tests/css/oracle.py check | grep -v ' [12]$' | sed 's/^/css-diff: FAIL oracle refuses good: /' > "$W/folder"
    [ ! -s "$W/folder" ] || { cat "$W/folder"; fail=1; }
    nstricter=$(ls $T/bad/*.css | xargs $PYTHON tests/css/oracle.py check | grep -c ' 1$')
    echo "css-diff: $nfiles files in good and bad; the grammar is stricter than the oracles on $nstricter of the bad ones (a rule of the syntax that tinycss2 and soupsieve leave to the property or the selector)"
fi

# (6) style sheets of well-known projects (bootstrap, bulma, font-awesome ...), pinned by sha256 in corpus/css/tests/real-world.txt:
#     fetched once into bench/cache/css-real, and run only when CSS_REAL=1
if [ -n "${CSS_REAL:-}" ]; then
    $PYTHON tests/css/oracle.py real bench/cache/css-real $T/real-world.txt > "$W/real.list" || fail=1
    nreal=$(wc -l < "$W/real.list")
    "$W/stylesheet" $(cat "$W/real.list") > "$W/real.out"
    nrefused=$(grep -c ' 0$' "$W/real.out")
    [ "$nrefused" = 0 ] || { grep ' 0$' "$W/real.out"; fail=1; }
    echo "css-diff: $nreal style sheets of well-known projects, the grammar refuses $nrefused"
fi

# (3) and (4) random sheets and their mutations
if [ $oracle = 1 ]; then
    $PYTHON tests/css/oracle.py gen "$N" "$SEED" "$W/g" || exit 1
    $PYTHON tests/css/oracle.py mut "$N" "$SEED" "$W/m" || exit 1
    ls "$W"/g/*.css | xargs "$W/stylesheet" > "$W/g.out"
    ls "$W"/m/*.css | xargs "$W/stylesheet" > "$W/m.out"
    ls "$W"/g/*.css | xargs $PYTHON tests/css/oracle.py check > "$W/g.ref"
    gbad=$(grep -c ' 0$' "$W/g.out"); gref=$(grep -vc ' 1$' "$W/g.ref")
    agree=0; loose=0; strict=0; meaning=0; mboth=0
    : > "$W/diff"
    while read f v; do
        r=$(cat "${f%.css}.ref")
        if [ "$r" = "$v" ]; then agree=$((agree+1))
        elif [ "$r" = 2 ]; then
            meaning=$((meaning+1)); [ "$v" = 1 ] || mboth=$((mboth+1))
        elif [ "$v" = 1 ]; then loose=$((loose+1)); echo "grammar accepts, oracle refuses: $f" >> "$W/diff"
        else strict=$((strict+1)); echo "grammar refuses, oracle accepts: $f" >> "$W/diff"; fi
    done < "$W/m.out"
    echo "css-diff: conforming style sheets: $N, the grammar refuses $gbad, the oracle refuses $gref"
    echo "css-diff: mutations: $agree agree, $meaning refused by soupsieve for what a selector means (either answer is fine), $loose grammar looser, $strict grammar stricter"
    [ "$loose$strict" = 00 ] || head -10 "$W/diff"
    [ "$gbad" = 0 ] && [ "$gref" = 0 ] && [ "$loose$strict" = 00 ] || fail=1
fi
[ -z "${DIFF_DIR:-}" ] || echo "css-diff: files in $W"
[ $fail = 0 ] || { echo "css-diff: FAIL"; exit 1; }
echo "css-diff: OK"
