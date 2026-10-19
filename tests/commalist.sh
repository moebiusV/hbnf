#!/bin/sh
# Comma lists: `n#m x` (RFCPLAN.md decision 12), checked by accepting and
# refusing lists of every size the five forms in tests/commalist/list.hbnf name.
#   HBNF=/path/to/hbnf sh tests/commalist.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/commalist/list.hbnf --backend=c > "$W/c.c" 2> "$W/err" \
    || { echo "commalist: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/c.c")
cp "$W/c.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
static int ok(const char *t) {
    $root out; char err[256]; size_t l, c;
    return parse_text(t, &out, err, sizeof err, &l, &c);
}
int main(void) {
    static const char *yes[] = {
        "one a;", "one a, b;", "one a,b,c,d;", "any ;", "any a;", "any a, b;",
        "two a, b;", "two a, b, c;", "three a, b;", "three a, b, c;",
        "pair a:b;", "pair a:b, c:d;", "pair a:b, c:d, e:f;" };
    static const char *no[] = {
        "one ;", "one a,;", "one ,a;", "one a b;", "any a,;", "two a;",
        "three a;", "three a, b, c, d;", "pair a:b, c;", "pair ;" };
    int bad = 0;
    unsigned i;
    for (i = 0; i < sizeof yes / sizeof *yes; i++)
        if (!ok(yes[i])) { printf("FAIL accept: %s\n", yes[i]); bad++; }
    for (i = 0; i < sizeof no / sizeof *no; i++)
        if (ok(no[i])) { printf("FAIL refuse: %s\n", no[i]); bad++; }
    return bad != 0;
}
EOC
cc -std=gnu11 -D_GNU_SOURCE -w -o "$W/cl" "$W/m.c" 2> "$W/cc" \
    || { echo "commalist: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
if "$W/cl"; then echo "commalist: OK (13 lists accepted, 10 refused)"; else echo "commalist: FAIL"; exit 1; fi
