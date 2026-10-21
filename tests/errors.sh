#!/bin/sh
# Error messages: every thing that could have stood at the failure is named
# ("expected one of"), and a construct that takes more than a couple of lines says
# where it began (a 'BEGIN' with no 'END').  The output must be tests/errors/expected.txt.
#   HBNF=/path/to/hbnf sh tests/errors.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
run() { # grammar files...
	g=$1; shift
	"$CLI" "$g" --backend=c > "$W/p.c" || { echo "errors: FAIL (generate $g)"; exit 1; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
	sed "s/ROOT_T/$root/" tests/errors/main.c > "$W/main.c"
	cat "$W/p.c" "$W/main.c" > "$W/m.c"
	cc -std=gnu11 -D_GNU_SOURCE -w -Itests/bsdinc "$W/m.c" -o "$W/m" || { echo "errors: FAIL (compile $g)"; exit 1; }
	"$W/m" "$@"
}
{
	run corpus/algol60/algol60.hbnf tests/errors/no-end.a60 tests/errors/paren.a60
	run corpus/json/json.hbnf tests/errors/json-comma.json
} > "$W/got.txt"
[ -z "${ERRORS_UPDATE:-}" ] || cp "$W/got.txt" tests/errors/expected.txt
if ! cmp -s "$W/got.txt" tests/errors/expected.txt; then
	echo "errors: FAIL"; diff -u tests/errors/expected.txt "$W/got.txt" | head -30; exit 1
fi

# The same in the other languages (tests/errors/block.hbnf; the driver reads open.blk and
# stray.blk beside it).  Zig and Rust give the same text; Ada puts `line N:` before it.
if command -v zig > /dev/null 2>&1; then
	mkdir -p "$W/zg" && cp tests/errors/*.blk "$W/zg/"
	"$CLI" tests/errors/block.hbnf --backend=zig > "$W/zg/block.zig" || { echo "errors: FAIL (zig generate)"; exit 1; }
	sed 's/GRAMMAR/block.zig/' tests/errors/main.zig > "$W/zg/main.zig"
	(cd "$W/zg" && zig build-exe main.zig -femit-bin=m > zig.out 2>&1) || { echo "errors: FAIL (zig compile)"; head "$W/zg/zig.out"; exit 1; }
	"$W/zg/m" > "$W/zg/got" 2>&1
	[ -z "${ERRORS_UPDATE:-}" ] || cp "$W/zg/got" tests/errors/block_zig.expected
	cmp -s "$W/zg/got" tests/errors/block_zig.expected || { echo "errors: FAIL (zig)"; diff "$W/zg/got" tests/errors/block_zig.expected | head; exit 1; }
fi
if command -v rustc > /dev/null 2>&1; then
	mkdir -p "$W/rs" && cp tests/errors/*.blk "$W/rs/"
	"$CLI" tests/errors/block.hbnf --backend=rust > "$W/rs/block.rs" || { echo "errors: FAIL (rust generate)"; exit 1; }
	sed 's/GRAMMAR/block/g' tests/errors/main.rs > "$W/rs/main.rs"
	(cd "$W/rs" && rustc --edition 2021 -A warnings -o m main.rs > rs.out 2>&1) || { echo "errors: FAIL (rust compile)"; head "$W/rs/rs.out"; exit 1; }
	"$W/rs/m" > "$W/rs/got" 2>&1
	[ -z "${ERRORS_UPDATE:-}" ] || cp "$W/rs/got" tests/errors/block_rust.expected
	cmp -s "$W/rs/got" tests/errors/block_rust.expected || { echo "errors: FAIL (rust)"; diff "$W/rs/got" tests/errors/block_rust.expected | head; exit 1; }
fi
if command -v gnatmake > /dev/null 2>&1; then
	mkdir -p "$W/ad" && cp tests/errors/*.blk tests/errors/main.adb "$W/ad/"
	"$CLI" tests/errors/block.hbnf --backend=ada --package=Block > "$W/ad/all.ada" || { echo "errors: FAIL (ada generate)"; exit 1; }
	(cd "$W/ad" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 main.adb -o m > gnat.out 2>&1) || { echo "errors: FAIL (ada compile)"; head "$W/ad/gnat.out"; exit 1; }
	(cd "$W/ad" && ./m > got 2>&1)
	[ -z "${ERRORS_UPDATE:-}" ] || cp "$W/ad/got" tests/errors/block_ada.expected
	cmp -s "$W/ad/got" tests/errors/block_ada.expected || { echo "errors: FAIL (ada)"; diff "$W/ad/got" tests/errors/block_ada.expected | head; exit 1; }
fi
echo "errors: OK (one of ..., and where an unfinished construct began; C, Zig, Rust, Ada)"
