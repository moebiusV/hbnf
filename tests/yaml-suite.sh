#!/bin/sh
# The YAML test suite (https://github.com/yaml/yaml-test-suite, branch data-2022-01-17): every
# case with an in.yaml, valid unless its directory holds a file `error`.  The parser hbnf makes
# from corpus/yaml/yaml.hbnf must agree on all of them but the ones listed in
# corpus/yaml/suite-gaps.txt (what the grammar does not yet decide); the run fails when a case
# differs that is not listed, and when a listed one no longer differs, so the list stays true.
# The suite is fetched into bench/cache/ the first time (YAML_TEST_SUITE=dir uses a copy).
#   HBNF=/path/to/hbnf sh tests/yaml-suite.sh
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
S=${YAML_TEST_SUITE:-bench/cache/yaml-test-suite}
if [ ! -d "$S" ]; then
    mkdir -p "$(dirname "$S")"
    git clone -q --depth 1 --branch data-2022-01-17 https://github.com/yaml/yaml-test-suite.git "$S" 2> /dev/null \
        || { echo "yaml-suite: SKIP (no copy of the suite at $S, and it could not be fetched)"; exit 0; }
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" "${YAML_GRAMMAR:-corpus/yaml/yaml.hbnf}" --backend=c --root=yaml > "$W/y.c" 2> "$W/err" \
    || { echo "yaml-suite: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/y.c")
cp "$W/y.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
#include <stdio.h>
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
cc -std=gnu11 -D_GNU_SOURCE -O1 -w -Iruntime -o "$W/y" "$W/m.c" 2> "$W/cc" \
    || { echo "yaml-suite: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
find "$S" -name in.yaml | sort > "$W/all"
xargs "$W/y" < "$W/all" > "$W/out"
: > "$W/differ"
valid=0; invalid=0
while read f v; do
    d=$(dirname "$f")
    id=${d#$S/}
    if [ -f "$d/error" ]; then want=0; invalid=$((invalid+1)); else want=1; valid=$((valid+1)); fi
    [ "$v" = "$want" ] || echo "$id" >> "$W/differ"
done < "$W/out"
sort "$W/differ" > "$W/differ.s"
grep -v '^#' corpus/yaml/suite-gaps.txt | grep . | sort > "$W/gaps.s"
echo "yaml-suite: $valid valid cases, $invalid invalid cases, $(wc -l < "$W/differ.s" | tr -d ' ') differ ($(wc -l < "$W/gaps.s" | tr -d ' ') listed)"
bad=0
for id in $(comm -23 "$W/differ.s" "$W/gaps.s"); do echo "FAIL not listed: $id"; bad=1; done
for id in $(comm -13 "$W/differ.s" "$W/gaps.s"); do echo "FAIL listed but now right (remove it from suite-gaps.txt): $id"; bad=1; done
[ $bad = 0 ] && echo "yaml-suite: OK" || exit 1
