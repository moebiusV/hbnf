#!/bin/sh
# TUTORIAL.md's programs: the shopping list of tutorial/shopping.hbnf read in C, Zig, Rust and
# Ada, each printing tutorial/expected.txt, and the C tools that work on any tree
# (tutorial/generic.c, tutorial/generic.expected).
#   HBNF=/path/to/hbnf sh tests/tutorial.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
G=tutorial/shopping.hbnf
fail=0
cp tutorial/main.* tutorial/tour.* tutorial/tools.* tutorial/generic.c "$W/"

"$CLI" $G --backend=c --ast --ast-tools --spans --writer > "$W/shopping.c" || { echo "tutorial: FAIL (generate c)"; exit 1; }
for prog in main generic tools; do
	want=tutorial/expected.txt; [ $prog = generic ] && want=tutorial/generic.expected; [ $prog = tools ] && want=tutorial/tools.expected
	if cc -w -o "$W/$prog" "$W/$prog.c" 2> "$W/cc.txt" && "$W/$prog" > "$W/$prog.out" 2>&1 \
	   && cmp -s "$W/$prog.out" $want; then
		echo "PASS $prog.c"
	else
		echo "FAIL $prog.c"; head -5 "$W/cc.txt"; diff "$W/$prog.out" $want | head; fail=$((fail+1))
	fi
done

if cc -w -o "$W/tourc" "$W/tour.c" 2> "$W/cc.txt" && "$W/tourc" > "$W/tourc.out" 2>&1 \
   && cmp -s "$W/tourc.out" tutorial/tour.expected; then
	echo "PASS tour.c"
else
	echo "FAIL tour.c"; head -5 "$W/cc.txt"; fail=$((fail+1))
fi

if command -v zig > /dev/null 2>&1; then
	"$CLI" $G --backend=zig --ast > "$W/shopping.zig" && (cd "$W" && zig build-exe main.zig -femit-bin=mz > zig.out 2>&1) \
	  && "$W/mz" > "$W/z.out" 2>&1 && cmp -s "$W/z.out" tutorial/expected.txt && echo "PASS main.zig" \
	  || { echo "FAIL main.zig"; head -5 "$W/zig.out"; fail=$((fail+1)); }
	(cd "$W" && zig build-exe tour.zig -femit-bin=tourz > zig.out 2>&1) && "$W/tourz" > "$W/tourz.out" 2>&1 \
	  && cmp -s "$W/tourz.out" tutorial/tour.expected && echo "PASS tour.zig" \
	  || { echo "FAIL tour.zig"; head -5 "$W/zig.out"; fail=$((fail+1)); }
	(cd "$W" && zig build-exe tools.zig -femit-bin=toolsz > zig.out 2>&1) && "$W/toolsz" > "$W/toolsz.out" 2>&1 \
	  && cmp -s "$W/toolsz.out" tutorial/tools.expected && echo "PASS tools.zig" \
	  || { echo "FAIL tools.zig"; head -5 "$W/zig.out"; fail=$((fail+1)); }
fi
if command -v rustc > /dev/null 2>&1; then
	"$CLI" $G --backend=rust --ast > "$W/shopping.rs" && (cd "$W" && rustc --edition 2021 -A warnings -o mr main.rs > rs.out 2>&1) \
	  && "$W/mr" > "$W/r.out" 2>&1 && cmp -s "$W/r.out" tutorial/expected.txt && echo "PASS main.rs" \
	  || { echo "FAIL main.rs"; head -5 "$W/rs.out"; fail=$((fail+1)); }
	(cd "$W" && rustc --edition 2021 -A warnings -o tourr tour.rs > rs.out 2>&1) && "$W/tourr" > "$W/tourr.out" 2>&1 \
	  && cmp -s "$W/tourr.out" tutorial/tour.expected && echo "PASS tour.rs" \
	  || { echo "FAIL tour.rs"; head -5 "$W/rs.out"; fail=$((fail+1)); }
	(cd "$W" && rustc --edition 2021 -A warnings -o toolsr tools.rs > rs.out 2>&1) && "$W/toolsr" > "$W/toolsr.out" 2>&1 \
	  && cmp -s "$W/toolsr.out" tutorial/tools.expected && echo "PASS tools.rs" \
	  || { echo "FAIL tools.rs"; head -5 "$W/rs.out"; fail=$((fail+1)); }
fi
if command -v gnatmake > /dev/null 2>&1; then
	"$CLI" $G --backend=ada --package=Shopping --ast > "$W/all.ada" && (cd "$W" && gnatchop -w all.ada > /dev/null 2>&1 \
	  && gnatmake -q -gnat2022 main.adb -o ma > gnat.out 2>&1) \
	  && "$W/ma" > "$W/a.out" 2>&1 && cmp -s "$W/a.out" tutorial/expected.txt && echo "PASS main.adb" \
	  || { echo "FAIL main.adb"; head -5 "$W/gnat.out"; fail=$((fail+1)); }
	(cd "$W" && gnatmake -q -gnat2022 tour.adb -o toura > gnat.out 2>&1) && "$W/toura" > "$W/toura.out" 2>&1 \
	  && cmp -s "$W/toura.out" tutorial/tour.expected && echo "PASS tour.adb" \
	  || { echo "FAIL tour.adb"; head -5 "$W/gnat.out"; fail=$((fail+1)); }
	(cd "$W" && gnatmake -q -gnat2022 tools.adb -o toolsa > gnat.out 2>&1) && "$W/toolsa" > "$W/toolsa.out" 2>&1 \
	  && cmp -s "$W/toolsa.out" tutorial/tools.expected && echo "PASS tools.adb" \
	  || { echo "FAIL tools.adb"; head -5 "$W/gnat.out"; fail=$((fail+1)); }
fi
[ $fail = 0 ] && echo "tutorial: OK" || { echo "tutorial: FAIL"; exit 1; }
