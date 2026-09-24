#!/bin/sh
# One schema through every backend (tests/portable/portable.hbnf): left
# recursion, %i literals and repetition bounds.  Each backend's driver
# parses good.conf and the *.bad configs and prints what it read; every
# one must print tests/portable/expected.txt.  C always runs; Rust, Zig and
# Ada run when rustc, zig and gnatmake are installed.
#   HBNF_CLI=/path/to/hbnf_cli sh tests/portable.sh     (default ./hbnf_cli)
set -u
cd "$(dirname "$0")/.."
CLI=${HBNF_CLI:-./hbnf_cli}
T=tests/portable
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
FILES="good.conf lead-comma.bad lead-op.bad pair-four.bad pair-one.bad slow-line4.bad slow-upper.bad trailing-op.bad"
rc=0

check() {   # check BACKEND OUTPUT
	if cmp -s "$2" $T/expected.txt; then
		echo "portable: $1 OK"
	else
		echo "portable: $1 FAIL"; diff -u $T/expected.txt "$2" | head -20; rc=1
	fi
}

"$CLI" $T/portable.hbnf --backend=c > "$W/p.c" || exit 1
cat "$W/p.c" $T/main.c > "$W/m.c"
if cc -std=gnu11 -D_GNU_SOURCE -Wall -Wno-unused-function -Werror -Itests/bsdinc "$W/m.c" -o "$W/c" 2> "$W/cc.txt"; then
	(cd $T && "$W/c" $FILES) > "$W/c.txt"; check C "$W/c.txt"
else
	echo "portable: C FAIL (compile)"; head -5 "$W/cc.txt"; rc=1
fi

if command -v rustc > /dev/null 2>&1; then
	mkdir "$W/rs"
	"$CLI" $T/portable.hbnf --backend=rust > "$W/rs/portable.rs" && cp $T/main.rs "$W/rs/"
	if (cd "$W/rs" && rustc -D warnings main.rs -o main) > "$W/rs.txt" 2>&1; then
		(cd $T && "$W/rs/main" $FILES) > "$W/rust.txt"; check Rust "$W/rust.txt"
	else
		echo "portable: Rust FAIL (compile)"; head -10 "$W/rs.txt"; rc=1
	fi
else
	echo "portable: Rust skipped (no rustc)"
fi

if command -v zig > /dev/null 2>&1; then
	mkdir "$W/zig"
	"$CLI" $T/portable.hbnf --backend=zig > "$W/zig/portable.zig"
	(cd $T && cp main.zig $FILES "$W/zig/")
	if (cd "$W/zig" && zig build-exe main.zig -femit-bin=main) > "$W/zig.err" 2>&1; then
		"$W/zig/main" 2> "$W/zig.txt"; check Zig "$W/zig.txt"
	else
		echo "portable: Zig FAIL (compile)"; head -10 "$W/zig.err"; rc=1
	fi
else
	echo "portable: Zig skipped (no zig)"
fi

if command -v gnatmake > /dev/null 2>&1; then
	mkdir "$W/ada"
	"$CLI" $T/portable.hbnf --backend=ada --package=Portable > "$W/ada/all.ada"
	cp $T/portable_main.adb "$W/ada/"
	if (cd "$W/ada" && gnatchop -q -w all.ada && gnatmake -q -gnat2022 portable_main.adb -o main) > "$W/ada.err" 2>&1; then
		(cd $T && "$W/ada/main" $FILES) > "$W/ada.txt"; check Ada "$W/ada.txt"
	else
		echo "portable: Ada FAIL (compile)"; head -10 "$W/ada.err"; rc=1
	fi
else
	echo "portable: Ada skipped (no gnatmake)"
fi
exit $rc
