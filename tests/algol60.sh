#!/bin/sh
# ALGOL 60 (corpus/algol60/algol60.hbnf): every program in corpus/algol60/tests/good
# must be accepted by the parser hbnf makes from the grammar, and every one in
# tests/bad refused.  The grammar is the Report's, arranged for ordered choice.
#   HBNF=/path/to/hbnf sh tests/algol60.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" corpus/algol60/algol60.hbnf --backend=c > "$W/a.c" 2> "$W/err" \
    || { echo "algol60: FAIL (generate: $(head -c 400 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/a.c")
cp "$W/a.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
int main(int argc, char **argv) {
    int i;
    for (i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "r");
        char *buf, err[512], *nl;
        long len;
        size_t line, col;
        $root out;
        if (!f) { printf("cannot open %s\n", argv[i]); return 2; }
        fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
        buf = malloc(len + 1);
        if (fread(buf, 1, len, f) != (size_t)len) return 2;
        buf[len] = 0; fclose(f);
        if (parse_text(buf, &out, err, sizeof err, &line, &col)) printf("accept %s\n", argv[i]);
        else { nl = strchr(err, '\n'); if (nl) *nl = 0; printf("refuse %s: %s\n", argv[i], err); }
        free(buf);
    }
    return 0;
}
EOC
cc -std=gnu11 -D_GNU_SOURCE -w -o "$W/a60" "$W/m.c" 2> "$W/cc" \
    || { echo "algol60: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
fail=0
for f in corpus/algol60/tests/good/*.a60; do
	r=$("$W/a60" "$f")
	case $r in accept*) ;; *) echo "FAIL good $f: $r"; fail=$((fail+1));; esac
done
for f in corpus/algol60/tests/bad/*.a60; do
	r=$("$W/a60" "$f")
	case $r in refuse*) ;; *) echo "FAIL bad $f: $r"; fail=$((fail+1));; esac
done
[ "$fail" -eq 0 ] && echo "algol60: OK ($(ls corpus/algol60/tests/good | wc -l) programs accepted, $(ls corpus/algol60/tests/bad | wc -l) refused)" || { echo "algol60: $fail FAIL"; exit 1; }
