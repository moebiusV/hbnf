#!/bin/sh
# Spans and parents (RFCPLAN.md 7d): with --spans every node knows where it is in
# the text (_pos, _end; node_span, node_where), and with --parents which node
# holds it (node_link, node_parent).  tests/spans/main.c walks the tree of
# tests/ast/ast.hbnf; the output must be tests/spans/expected.txt.
#   HBNF=/path/to/hbnf sh tests/spans.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/ast/ast.hbnf --backend=c --ast --spans --parents > "$W/a.c" \
    || { echo "spans: FAIL (generate)"; exit 1; }
cat "$W/a.c" tests/spans/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/spans" \
    2> "$W/cc.txt" || { echo "spans: FAIL (compile)"; head -5 "$W/cc.txt"; exit 1; }
"$W/spans" > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/spans/expected.txt; then
	echo "spans: FAIL"; diff -u tests/spans/expected.txt "$W/got.txt" | head -30; exit 1
fi

# The same in Rust, Zig and Ada: the lines C printed.
if command -v rustc > /dev/null 2>&1; then
	"$CLI" tests/ast/ast.hbnf --backend=rust --ast --spans --parents > "$W/ast.rs" || { echo "spans: FAIL (rust generate)"; exit 1; }
	cp tests/spans/main.rs "$W/m.rs"
	(cd "$W" && rustc --edition 2021 -A warnings -o mr m.rs > rs.txt 2>&1) || { echo "spans: FAIL (rust compile)"; head -5 "$W/rs.txt"; exit 1; }
	"$W/mr" > "$W/rust.txt" 2>&1
	cmp -s "$W/rust.txt" tests/spans/expected.txt || { echo "spans: FAIL (rust)"; diff "$W/rust.txt" tests/spans/expected.txt | head; exit 1; }
fi
if command -v zig > /dev/null 2>&1; then
	"$CLI" tests/ast/ast.hbnf --backend=zig --ast --spans --parents > "$W/ast.zig" || { echo "spans: FAIL (zig generate)"; exit 1; }
	cp tests/spans/main.zig "$W/m.zig"
	(cd "$W" && zig build-exe m.zig -femit-bin=mz > zg.txt 2>&1) || { echo "spans: FAIL (zig compile)"; head -5 "$W/zg.txt"; exit 1; }
	"$W/mz" > "$W/zig.txt" 2>&1
	cmp -s "$W/zig.txt" tests/spans/expected.txt || { echo "spans: FAIL (zig)"; diff "$W/zig.txt" tests/spans/expected.txt | head; exit 1; }
fi
if command -v gnatmake > /dev/null 2>&1; then
	mkdir -p "$W/ad"
	"$CLI" tests/ast/ast.hbnf --backend=ada --package=Ast --ast --spans --parents > "$W/ad/all.ada" || { echo "spans: FAIL (ada generate)"; exit 1; }
	cp tests/spans/main.adb "$W/ad/"
	(cd "$W/ad" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 main.adb -o m > gnat.txt 2>&1) \
	  || { echo "spans: FAIL (ada compile)"; head -5 "$W/ad/gnat.txt"; exit 1; }
	"$W/ad/m" > "$W/ad/out.txt" 2>&1
	cmp -s "$W/ad/out.txt" tests/spans/expected.txt || { echo "spans: FAIL (ada)"; diff "$W/ad/out.txt" tests/spans/expected.txt | head; exit 1; }
fi
echo "spans: OK (places and parents; the same in Rust, Zig and Ada)"
