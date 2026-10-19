#!/bin/sh
# A grammar in tree-sitter against hbnf (ALGOL 60 by default; TSD_GRAMMAR, TSD_ORACLE
# and TSD_EXT choose another, e.g. corpus/json/json.hbnf with tests/json/oracle.py and
# json): the grammar.js hbnf writes, built into a parser by the real tree-sitter, and the
# parser hbnf makes, are asked about the same texts: random sentences of the Report
# and random mutations of them (the oracle makes both).  Every sentence must
# parse in tree-sitter; where a mutation is accepted by one and not the other is
# counted.  Needs TS_CLI and TS_NODE_DIR as tests/treesitter.sh does.
#   HBNF=... TS_NODE_DIR=... TS_CLI=... sh tests/treesitter-diff.sh [N [SEED]]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
N=${1:-500}; SEED=${2:-1}
if [ -z "${TS_CLI:-}" ] || [ -z "${TS_NODE_DIR:-}" ]; then
	echo "treesitter-diff: SKIP (no TS_CLI / TS_NODE_DIR)"; exit 0
fi
W=${DIFF_DIR:-$(mktemp -d)}
[ -n "${DIFF_DIR:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
G=${TSD_GRAMMAR:-corpus/algol60/algol60.hbnf}
ORACLE=${TSD_ORACLE:-tests/algol60/reference.py}
EXT=${TSD_EXT:-a60}
conf=$(sh tests/ts-build.sh "$G" "$W/ts") || { echo "treesitter-diff: FAIL (build)"; exit 1; }
"$CLI" "$G" --backend=c > "$W/a.c" 2> "$W/err" || { echo "treesitter-diff: FAIL (hbnf)"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/a.c")
cp "$W/a.c" "$W/m.c"
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
cc -std=gnu11 -D_GNU_SOURCE -O1 -w -o "$W/a60" "$W/m.c" || { echo "treesitter-diff: FAIL (compile)"; exit 1; }
python3 -I "$ORACLE" gen "$N" "$SEED" "$W/g" || exit 1
python3 -I "$ORACLE" mut "$N" "$SEED" "$W/m" || exit 1
export PATH="$TS_NODE_DIR:$PATH"
for d in g m; do
	ls "$W/$d"/*.$EXT > "$W/$d.paths"
	xargs "$W/a60" < "$W/$d.paths" > "$W/$d.hbnf"
	( cd "$W/ts" && "$TS_CLI" parse -q --paths "$W/$d.paths" 2>/dev/null ) | cut -f1 | sort > "$W/$d.tsfail"
done
gts=$(wc -l < "$W/g.tsfail"); ghb=$(grep -c ' 0$' "$W/g.hbnf")
both=0; hb_only=0; ts_only=0; none=0
while read f v; do
	if grep -qxF "$f" "$W/m.tsfail"; then t=0; else t=1; fi
	if [ "$v" = 1 ] && [ $t = 1 ]; then both=$((both+1))
	elif [ "$v" = 0 ] && [ $t = 0 ]; then none=$((none+1))
	elif [ "$v" = 1 ]; then hb_only=$((hb_only+1)); echo "$f" >> "$W/hb_only"
	else ts_only=$((ts_only+1)); echo "$f" >> "$W/ts_only"; fi
done < "$W/m.hbnf"
echo "treesitter-diff: Report sentences: $N, hbnf refuses $ghb, tree-sitter refuses $gts"
echo "treesitter-diff: mutations: $both accepted by both, $none refused by both, $hb_only only by hbnf, $ts_only only by tree-sitter"
[ -z "${DIFF_DIR:-}" ] || echo "treesitter-diff: files in $W"
[ "$gts" = 0 ] || exit 1
