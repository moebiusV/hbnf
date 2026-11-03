#!/bin/sh
# JavaScript against V8 (tests/js/oracle.py, through py_mini_racer): the parser hbnf makes from corpus/js/js.hbnf (the Script
# goal) and V8 are asked about the same texts.
# (1) Random programs (the generator keeps V8 happy: a few it gets wrong are compared like the rest).  (2) Random
# mutations of them -- a character deleted, inserted, replaced, swapped, a piece doubled, the text cut, a line end moved --
# must get the same answer, except where V8 refuses for an early error (a rule of the static semantics: an assignment to a
# number, a duplicate `let` ...: the oracle marks those L, and the grammar may accept or refuse them), and where `await` or
# `yield` stands outside the function that gives it a meaning (the grammar does not know which functions are async).
# (3) Every code point above 127 as the first and as a later character of a name, against V8's tables.  (4) The real
# scripts of this machine (jQuery, highlight.js ...) when there are any under /usr/share: all must be accepted.
#   HBNF=/path/to/hbnf JS_PYTHON=python3-with-mini-racer sh tests/js-diff.sh [N [SEED]]      (HBNF_FLAGS= adds generator flags)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
N=${1:-3000}; SEED=${2:-1}
PY=${JS_PYTHON:-python3}
"$PY" -c 'import py_mini_racer' 2> /dev/null \
    || { echo "js-diff: SKIP ($PY has no py_mini_racer: pip install mini-racer, or set JS_PYTHON)"; exit 0; }
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
"$CLI" corpus/js/js.hbnf --backend=c ${HBNF_FLAGS:-} > "$W/j.c" 2> "$W/err" \
    || { echo "js-diff: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/j.c")
cp "$W/j.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
/* files named on the command line, "FILE 1|0" for each; with -z, the texts on the standard input, separated by NUL,
   and one 1 or 0 for each on the standard output */
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
        buf[len] = 0;
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
    || { echo "js-diff: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
rc=0
"$PY" -I tests/js/oracle.py gen "$N" "$SEED" "$W/g" 2> "$W/gen.err" || { echo "js-diff: FAIL (oracle gen)"; exit 1; }
"$PY" -I tests/js/oracle.py mut "$N" "$SEED" "$W/m" || { echo "js-diff: FAIL (oracle mut)"; exit 1; }
"$PY" -I tests/js/oracle.py compare "$W/j" "$W/g" g || rc=1
"$PY" -I tests/js/oracle.py compare "$W/j" "$W/m" m || rc=1
# every code point above 127 as the first and as a later character of a name
"$PY" -I tests/js/oracle.py ids "$W/n" || exit 1
"$W/j" -z < "$W/n/ids.in" | tr -d '\n' > "$W/n/ids.out"
ncp=$(wc -c < "$W/n/ids.ref")
nbad=$(cmp -l "$W/n/ids.ref" "$W/n/ids.out" | wc -l)
echo "js-diff: name characters: $((ncp / 2)) code points, $nbad differ from V8's tables"
[ "$nbad" = 0 ] || rc=1
# the scripts that are on this machine
if [ -d /usr/share ]; then
    real=$(find /usr/share /usr/lib/node_modules -type f -name '*.js' -size +0 2> /dev/null | head -2000)
    nreal=0; nrefused=0
    for f in $real; do
        nreal=$((nreal + 1))
        "$W/j" "$f" | grep -q ' 1$' || { nrefused=$((nrefused + 1)); echo "refused: $f" >> "$W/real.refused"; }
    done
    if [ "$nreal" -gt 0 ]; then
        wrong=0
        [ ! -s "$W/real.refused" ] || wrong=$("$PY" -I tests/js/oracle.py check $(sed 's/^refused: //' "$W/real.refused") | grep -c ' 1$')
        echo "js-diff: scripts found under /usr/share: $nreal, refused $nrefused (ES modules are not Scripts), of which V8 accepts $wrong"
        [ "$wrong" = 0 ] || rc=1
    fi
fi
[ -z "${DIFF_DIR:-}" ] || echo "js-diff: files in $W"
[ $rc = 0 ] && echo "js-diff: OK" || { echo "js-diff: FAIL"; exit 1; }
