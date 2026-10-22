#!/bin/sh
# Back-references (`name %as tag` ... `%same tag`): a closing tag must repeat the
# text of the opening one.  tests/backref/tags.hbnf is the whole of XML's element
# structure; the output of tests/backref/main.c must be tests/backref/expected.txt,
# and with --writer every accepted document must be written back as it was.
#   HBNF=/path/to/hbnf sh tests/backref.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/backref/tags.hbnf --backend=c --writer > "$W/t.c" 2> "$W/err" \
    || { echo "backref: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/t.c")
cat "$W/t.c" tests/backref/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE "-DROOT=$root" -Wall -Wno-unused-function -Werror -o "$W/t" "$W/m.c" 2> "$W/cc" \
    || { echo "backref: FAIL (compile)"; head -8 "$W/cc"; exit 1; }
"$W/t" > "$W/got.txt"
[ -z "${BACKREF_UPDATE:-}" ] || cp "$W/got.txt" tests/backref/expected.txt
cmp -s "$W/got.txt" tests/backref/expected.txt || { echo "backref: FAIL"; diff -u tests/backref/expected.txt "$W/got.txt" | head -20; exit 1; }
# the writer gives back what was read
wroot=$(sed -n 's/^static size_t write_\([A-Za-z0-9_]*\) (.*/\1/p' "$W/t.c" | head -1)
cat "$W/t.c" > "$W/w.c"
cat >> "$W/w.c" <<EOC
#include <stdlib.h>
int main(void) {
    static const char *docs[] = { "<a></a>", "<a>t</a>", "<a><b>x</b><b>y</b></a>", "p<a><a>q</a></a>r", NULL };
    int i, bad = 0;
    for (i = 0; docs[i]; i++) {
        $root out; char err[256]; size_t l, c, n; char *s;
        if (!parse_text(docs[i], &out, err, sizeof err, &l, &c)) { printf("no parse %s\n", docs[i]); bad++; continue; }
        n = write_$wroot (&out, NULL, 0);
        s = malloc (n + 1); write_$wroot (&out, s, n + 1);
        if (strcmp (s, docs[i])) { printf("written %s as %s\n", docs[i], s); bad++; }
    }
    return bad != 0;
}
EOC
cc -std=gnu11 -D_GNU_SOURCE -w -o "$W/w" "$W/w.c" 2> "$W/cc2" || { echo "backref: FAIL (compile writer)"; head -5 "$W/cc2"; exit 1; }
"$W/w" || { echo "backref: FAIL (writer)"; exit 1; }

# The same in Rust, Zig and Ada: the lines C printed (tests/backref/main.{rs,zig,adb}).
G=tests/backref/tags.hbnf
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" $G --backend=rust > "$d/tags.rs" && cp tests/backref/main.rs "$d/m.rs" \
	  && (cd "$d" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1) && "$d/m" > "$d/out" 2>&1 \
	  && cmp -s "$d/out" tests/backref/expected.txt || { echo "backref: FAIL (rust)"; head -5 "$d/cc.txt" 2>/dev/null; diff "$d/out" tests/backref/expected.txt | head -5; exit 1; }
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" $G --backend=zig > "$d/tags.zig" && cp tests/backref/main.zig "$d/m.zig" \
	  && (cd "$d" && zig build-exe m.zig -femit-bin=m > cc.txt 2>&1) && "$d/m" > "$d/out" 2>&1 \
	  && cmp -s "$d/out" tests/backref/expected.txt || { echo "backref: FAIL (zig)"; head -5 "$d/cc.txt" 2>/dev/null; diff "$d/out" tests/backref/expected.txt | head -5; exit 1; }
fi
if command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" $G --backend=ada --package=Tags > "$d/all.ada" && cp tests/backref/main.adb "$d/" \
	  && (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 main.adb -o m > cc.txt 2>&1) \
	  && "$d/m" > "$d/out" 2>&1 && cmp -s "$d/out" tests/backref/expected.txt \
	  || { echo "backref: FAIL (ada)"; grep -v warning "$d/cc.txt" 2>/dev/null | head -5; diff "$d/out" tests/backref/expected.txt | head -5; exit 1; }
fi
echo "backref: OK (a closing tag repeats the opening one; the writer repeats it too; Rust, Zig and Ada parse it)"
