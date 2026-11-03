#!/bin/sh
# GraphQL's lexical grammar against a second reading of the specification (tests/graphql/oracle.py, a
# hand-made scanner, since no GraphQL library is installed): the parser hbnf makes from
# corpus/graphql/graphql.hbnf (C backend) and the oracle are asked about N random documents
# `{ a(x: S) }`, S a run of pieces chosen to hit the corners (quotes and backslashes, numbers with a
# dot or an `e`, names, commas, comments, a control character, the byte order mark).  Any difference
# is a failure.  The hand-written cases are tests/graphql.sh's.
#   HBNF=/path/to/hbnf sh tests/graphql-diff.sh [N [SEED]]
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
N=${1:-20000}; SEED=${2:-1}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" corpus/graphql/graphql.hbnf --backend=c > "$W/g.c" 2> "$W/err" \
    || { echo "graphql-diff: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/g.c")
cp "$W/g.c" "$W/m.c"
cat >> "$W/m.c" <<EOC
/* documents on standard input, separated by NUL: 1 if the parser takes one, 0 if not, a line each */
int main(void) {
    static char buf[1 << 26];
    size_t n = fread(buf, 1, sizeof buf - 1, stdin), i = 0;
    buf[n] = 0;
    while (i < n) {
        $root out; char err[512]; size_t l, c;
        printf("%d\n", parse_text(buf + i, &out, err, sizeof err, &l, &c) ? 1 : 0);
        i += strlen(buf + i) + 1;
    }
    return 0;
}
EOC
cc -std=gnu11 -D_GNU_SOURCE -O1 -w -o "$W/g" "$W/m.c" 2> "$W/cc" \
    || { echo "graphql-diff: FAIL (compile)"; head -5 "$W/cc"; exit 1; }
python3 -I tests/graphql/oracle.py "$N" "$SEED" "$W/docs" || exit 1
"$W/g" < "$W/docs" > "$W/out"
valid=$(grep -c 1 "$W/docs.ref")
diffs=$(paste "$W/out" "$W/docs.ref" | awk '$1 != $2 { n++ } END { print n + 0 }')
echo "graphql-diff: $N documents, the oracle takes $valid, $diffs differences"
if [ "$diffs" != 0 ]; then
    paste "$W/out" "$W/docs.ref" | awk '$1 != $2 { print NR }' | head -5
    exit 1
fi
echo "graphql-diff: OK"
