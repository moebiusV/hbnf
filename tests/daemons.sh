#!/bin/sh
# Daemon grammars against sample configs.  tests/daemons/<grammar>/*.conf must
# all be accepted by the plain C parser generated from grammars/<grammar>.hbnf,
# and each *.bad rejected.  They are parsed in their own directory, as pfctl's
# regress runs, so an `include "x.inc"` there finds x.inc.
# server.hbnf cannot catch what only a real grammar exercises (keyword enums
# such as pfctl's `dir = "in" / "out"`, keyword-led option lists).
#   HBNF_CLI=/path/to/hbnf_cli sh tests/daemons.sh      (default ./hbnf_cli)
# Prints one "<grammar>: OK" or "<grammar>: FAIL ..." line per grammar.
set -u
cd "$(dirname "$0")/.."
CLI=${HBNF_CLI:-./hbnf_cli}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
for d in tests/daemons/*/; do
	g=$(basename "$d")
	if ! "$CLI" "grammars/$g.hbnf" --backend=c >"$W/$g.c" 2>"$W/$g.err"; then
		echo "$g: FAIL (generate: $(tail -1 "$W/$g.err"))"; rc=1; continue
	fi
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$g.c")
	cat "$W/$g.c" >"$W/$g.main.c"
	cat >>"$W/$g.main.c" <<EOC
int main(int argc, char **argv) {
    int bad = 0;
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "r");
        char *buf; long len;
        if (!f) { printf("%s: cannot open\n", argv[i]); bad = 1; continue; }
        fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
        buf = malloc((size_t)len + 1);
        if (fread(buf, 1, (size_t)len, f) != (size_t)len) len = 0;
        buf[len] = '\0'; fclose(f);
        $root out; char err[512]; size_t l = 0, c = 0;
        if (!parse_text(buf, &out, err, sizeof err, &l, &c)) {
            printf("%s:%zu:%zu: %s\n", argv[i], l, c, err); bad = 1;
        }
        free(buf);
    }
    return bad;
}
EOC
	if ! gcc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$W/$g.main.c" -o "$W/$g" 2>"$W/$g.err"; then
		echo "$g: FAIL (compile: $(grep -m1 error "$W/$g.err"))"; rc=1; continue
	fi
	nbad=0; wrong=""
	for b in "$d"*.bad; do
		[ -f "$b" ] || continue
		nbad=$((nbad + 1))
		(cd "$d" && "$W/$g" "$(basename "$b")") >/dev/null && wrong="$wrong $(basename "$b")"
	done
	if [ -n "$wrong" ]; then
		echo "$g: FAIL (accepted:$wrong)"; rc=1
	elif out=$(cd "$d" && "$W/$g" *.conf); then
		echo "$g: OK ($(ls "$d"*.conf | wc -l | tr -d ' ') configs, $nbad rejected)"
	else
		echo "$g: FAIL"; printf '%s\n' "$out" | head -8; rc=1
	fi
done
exit $rc
