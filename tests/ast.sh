#!/bin/sh
# The AST and its walker (RFCPLAN.md 7d): every node records the alternative it
# took, and walk_<rule> calls back on entering and leaving each node with the
# path that led to it.  tests/ast/main.c walks tests/ast/ast.hbnf's tree; the
# output must be tests/ast/expected.txt.
#   HBNF=/path/to/hbnf sh tests/ast.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/ast/ast.hbnf --backend=c --ast-tools > "$W/a.c" || { echo "ast: FAIL (generate)"; exit 1; }
cat "$W/a.c" tests/ast/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/ast" \
    2> "$W/cc.txt" || { echo "ast: FAIL (compile)"; head -5 "$W/cc.txt"; exit 1; }
"$W/ast" > "$W/got.txt"
if ! cmp -s "$W/got.txt" tests/ast/expected.txt; then
	echo "ast: FAIL"; diff -u tests/ast/expected.txt "$W/got.txt" | head -20; exit 1
fi

# The same walk and dump in Rust (--ast): the first three sections must be the ones C printed, and
# two trees are equal when their dumps are.
if command -v rustc > /dev/null 2>&1; then
	"$CLI" tests/ast/ast.hbnf --backend=rust --ast > "$W/ast.rs" || { echo "ast: FAIL (rust generate)"; exit 1; }
	cp tests/ast/dump_main.rs "$W/m.rs"
	(cd "$W" && rustc --edition 2021 -A warnings -o mr m.rs > rs.txt 2>&1) || { echo "ast: FAIL (rust compile)"; head -5 "$W/rs.txt"; exit 1; }
	"$W/mr" > "$W/rust.txt"
	sed -n '1,/^(config/p' tests/ast/expected.txt > "$W/want3.txt"
	sed '/^== equal/,$d' "$W/rust.txt" > "$W/got3.txt"
	cmp -s "$W/got3.txt" "$W/want3.txt" || { echo "ast: FAIL (rust)"; diff "$W/got3.txt" "$W/want3.txt" | head; exit 1; }
	grep -q "^same text: true" "$W/rust.txt" && grep -q "^other text: false" "$W/rust.txt" || { echo "ast: FAIL (rust equal)"; exit 1; }
fi
if command -v zig > /dev/null 2>&1; then
	"$CLI" tests/ast/ast.hbnf --backend=zig --ast > "$W/ast.zig" || { echo "ast: FAIL (zig generate)"; exit 1; }
	cp tests/ast/dump_main.zig "$W/m.zig"
	(cd "$W" && zig build-exe m.zig -femit-bin=mz > zg.txt 2>&1) || { echo "ast: FAIL (zig compile)"; head -5 "$W/zg.txt"; exit 1; }
	"$W/mz" > "$W/zig.txt" 2>&1
	sed -n '1,/^(config/p' tests/ast/expected.txt > "$W/want3.txt"
	sed '/^== equal/,$d' "$W/zig.txt" > "$W/gotz.txt"
	cmp -s "$W/gotz.txt" "$W/want3.txt" || { echo "ast: FAIL (zig)"; diff "$W/gotz.txt" "$W/want3.txt" | head; exit 1; }
	grep -q "^same text: true" "$W/zig.txt" && grep -q "^other text: false" "$W/zig.txt" || { echo "ast: FAIL (zig equal)"; exit 1; }
fi
if command -v gnatmake > /dev/null 2>&1; then
	mkdir -p "$W/ad"
	"$CLI" tests/ast/ast.hbnf --backend=ada --package=Ast --ast > "$W/ad/all.ada" || { echo "ast: FAIL (ada generate)"; exit 1; }
	cp tests/ast/dump_main.adb "$W/ad/"
	(cd "$W/ad" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 dump_main.adb -o m > gnat.txt 2>&1) \
	  || { echo "ast: FAIL (ada compile)"; head -5 "$W/ad/gnat.txt"; exit 1; }
	"$W/ad/m" > "$W/ad/out.txt" 2>&1
	sed -n '1,/^(config/p' tests/ast/expected.txt > "$W/want3.txt"
	sed '/^== equal/,$d' "$W/ad/out.txt" > "$W/ad/got3.txt"
	cmp -s "$W/ad/got3.txt" "$W/want3.txt" || { echo "ast: FAIL (ada)"; diff "$W/ad/got3.txt" "$W/want3.txt" | head; exit 1; }
	grep -q "^same text: TRUE" "$W/ad/out.txt" && grep -q "^other text: FALSE" "$W/ad/out.txt" || { echo "ast: FAIL (ada equal)"; exit 1; }
fi
echo "ast: OK (the walk, a skip, a stop; the same walk and dump in Rust, Zig and Ada)"
