#!/bin/sh
# The text writer (RFCPLAN.md 7c): generate with --writer, then for each input
# parse, write, re-parse, write again; the output must parse and be stable.
#   HBNF=/path/to/hbnf sh tests/writer.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0

# round NAME GRAMMAR INPUT...
round() {
	n=$1; g=$2; shift 2
	if ! "$CLI" "$g" --backend=c --writer > "$W/$n.c" 2> "$W/$n.err"; then
		echo "FAIL $n: generation: $(tail -2 "$W/$n.err")"; fail=$((fail+1)); return
	fi
	outt=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$n.c")
	root=$(sed -n 's/^static size_t write_\([A-Za-z0-9_]*\) (.*/\1/p' "$W/$n.c" | head -1)
	if [ -z "$outt" ] || [ -z "$root" ]; then
		echo "FAIL $n: no parse_text or write_ in the generated parser"; fail=$((fail+1)); return
	fi
	{ cat "$W/$n.c"; printf '#include <stdlib.h>\n'; cat tests/writer/rt_main.c; } > "$W/${n}_m.c"
	if ! cc -std=gnu11 -D_GNU_SOURCE -Wno-unused-function -Itests/bsdinc -DOUT_T="$outt" -DWRITE="write_$root" \
	     "$W/${n}_m.c" -o "$W/$n" 2> "$W/$n.cc"; then
		echo "FAIL $n: cc"; head -8 "$W/$n.cc"; fail=$((fail+1)); return
	fi
	out=$("$W/$n" "$@" 2>&1) || { echo "FAIL $n"; echo "$out" | cut -c1-400 | head -30; fail=$((fail+1)); return; }
	echo "PASS $n: $(echo "$out" | grep -c ': ok') files round-tripped, $(echo "$out" | grep -c SKIP) not parsed (the .bad ones)"
}

round obconf grammars/obconf_roundtrip.hbnf tests/accept/*.conf
round json corpus/json/json.hbnf corpus/json/tests/good/*.json corpus/json/tests/bad/*.json
round mustache corpus/mustache/mustache.hbnf corpus/mustache/tests/good/*.mustache corpus/mustache/tests/bad/*.mustache
for d in tests/daemons/*/; do
	g=$(basename "$d")
	round "$g" "grammars/obconf_$g.hbnf" "$d"*.conf
done


# The same gate in Rust, Zig and Ada (--writer --ast): every file the language's parser reads is
# written and read back to the same tree (the dump), and the second write is the first.  A grammar
# with a scanner written in C (a `jet`) or with %as/%same is parsed by C alone so far, so some files
# are not parsed here ("skipped").  tests/writer/rt_main.{rs,zig,adb} are the drivers.
cap() { printf '%s' "$1" | awk '{ print toupper(substr($0,1,1)) substr($0,2) }'; }

rt_rust() {
	command -v rustc > /dev/null 2>&1 || return 0
	n=$1; g=$2; shift 2
	d=$W/rs_$n; mkdir -p "$d"
	if ! "$CLI" "$g" --backend=rust --writer --ast > "$d/$n.rs" 2> "$d/err"; then
		echo "FAIL $n (rust): generation: $(tail -2 "$d/err")"; fail=$((fail+1)); return
	fi
	root=$(sed -n 's/^pub fn write_\([A-Za-z0-9_]*\)(.*/\1/p' "$d/$n.rs" | head -1)
	sed "s/MODULE/$n/g; s/ROOT/$root/g" tests/writer/rt_main.rs > "$d/m.rs"
	if ! (cd "$d" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1); then
		echo "FAIL $n (rust): rustc"; head -8 "$d/cc.txt"; fail=$((fail+1)); return
	fi
	out=$("$d/m" "$@" 2>&1) || { echo "FAIL $n (rust)"; echo "$out" | cut -c1-300 | head -20; fail=$((fail+1)); return; }
	echo "PASS $n (rust): $(echo "$out" | grep -c ': ok') files round-tripped, $(echo "$out" | grep -c SKIP) not parsed"
}

rt_zig() {
	command -v zig > /dev/null 2>&1 || return 0
	n=$1; g=$2; shift 2
	d=$W/zg_$n; mkdir -p "$d"
	if ! "$CLI" "$g" --backend=zig --writer --ast > "$d/$n.zig" 2> "$d/err"; then
		echo "FAIL $n (zig): generation: $(tail -2 "$d/err")"; fail=$((fail+1)); return
	fi
	root=$(sed -n 's/^pub fn write_\([A-Za-z0-9_]*\)(.*/\1/p' "$d/$n.zig" | head -1)
	: > "$d/files.txt"; i=0
	for f in "$@"; do
		i=$((i+1)); cp "$f" "$d/f$i.dat"
		printf '    .{ .name = "%s", .data = @embedFile("f%d.dat") },\n' "$f" "$i" >> "$d/files.txt"
	done
	sed "s/MODULE/$n.zig/g; s/ROOT/$root/g" tests/writer/rt_main.zig \
	  | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if ! (cd "$d" && zig build-exe m.zig -femit-bin=m > cc.txt 2>&1); then
		echo "FAIL $n (zig): zig"; head -8 "$d/cc.txt"; fail=$((fail+1)); return
	fi
	out=$("$d/m" 2>&1) || { echo "FAIL $n (zig)"; echo "$out" | cut -c1-300 | head -20; fail=$((fail+1)); return; }
	echo "PASS $n (zig): $(echo "$out" | grep -c ': ok') files round-tripped, $(echo "$out" | grep -c SKIP) not parsed"
}

rt_ada() {
	command -v gnatmake > /dev/null 2>&1 || return 0
	n=$1; g=$2; shift 2
	d=$W/ad_$n; mkdir -p "$d"; pk=$(cap "$n")
	if ! "$CLI" "$g" --backend=ada --package="$pk" --writer --ast > "$d/all.ada" 2> "$d/err"; then
		echo "FAIL $n (ada): generation: $(tail -2 "$d/err")"; fail=$((fail+1)); return
	fi
	root=$(sed -n 's/^   procedure Write_\([A-Za-z0-9_]*\) (V.*/\1/p' "$d/all.ada" | head -1)
	sed "s/MODULE/$pk/g; s/ROOT/$root/g" tests/writer/rt_main.adb > "$d/rt_main.adb"
	if ! (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 rt_main.adb -o m > cc.txt 2>&1); then
		echo "FAIL $n (ada): gnat"; grep -v warning "$d/cc.txt" | head -8; fail=$((fail+1)); return
	fi
	out=$("$d/m" "$@" 2>&1) || { echo "FAIL $n (ada)"; echo "$out" | cut -c1-300 | head -20; fail=$((fail+1)); return; }
	echo "PASS $n (ada): $(echo "$out" | grep -c ': ok') files round-tripped, $(echo "$out" | grep -c SKIP) not parsed"
}

others() { rt_rust "$@"; rt_zig "$@"; rt_ada "$@"; }

others json corpus/json/json.hbnf corpus/json/tests/good/*.json corpus/json/tests/bad/*.json
others obconf grammars/obconf_roundtrip.hbnf tests/accept/*.conf
# (not in Ada: the report's rule names have two underscores in a row, which Ada does not allow)
rt_rust algol60 corpus/algol60/algol60.hbnf corpus/algol60/tests/good/*.a60
rt_zig algol60 corpus/algol60/algol60.hbnf corpus/algol60/tests/good/*.a60
for d in tests/daemons/*/; do
	g=$(basename "$d")
	others "$g" "grammars/obconf_$g.hbnf" "$d"*.conf
done

# A pretty-printer's say in how the tree is written (Layout): tests/writer/layout_main.* write
# tutorial/shopping.hbnf's tree with a newline before every "buy" but the first, "from" in capitals,
# and a log of the rules entered; the output must be tests/writer/layout.expected.
layout() {
	G=tutorial/shopping.hbnf
	if command -v rustc > /dev/null 2>&1; then
		d=$W/lay_rs; mkdir -p "$d"
		"$CLI" $G --backend=rust --writer > "$d/shopping.rs" && cp tests/writer/layout_main.rs "$d/m.rs" \
		  && (cd "$d" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1) && "$d/m" > "$d/out" 2>&1 \
		  && cmp -s "$d/out" tests/writer/layout.expected && echo "PASS layout (rust)" \
		  || { echo "FAIL layout (rust)"; head -5 "$d/cc.txt" 2>/dev/null; fail=$((fail+1)); }
	fi
	if command -v zig > /dev/null 2>&1; then
		d=$W/lay_zg; mkdir -p "$d"
		"$CLI" $G --backend=zig --writer > "$d/shopping.zig" && cp tests/writer/layout_main.zig "$d/m.zig" \
		  && (cd "$d" && zig build-exe m.zig -femit-bin=m > cc.txt 2>&1) && "$d/m" > "$d/out" 2>&1 \
		  && cmp -s "$d/out" tests/writer/layout.expected && echo "PASS layout (zig)" \
		  || { echo "FAIL layout (zig)"; head -5 "$d/cc.txt" 2>/dev/null; fail=$((fail+1)); }
	fi
	if command -v gnatmake > /dev/null 2>&1; then
		d=$W/lay_ad; mkdir -p "$d"
		"$CLI" $G --backend=ada --package=Shopping --writer > "$d/all.ada" && cp tests/writer/layout_main.adb "$d/" \
		  && (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 layout_main.adb -o m > cc.txt 2>&1) \
		  && "$d/m" > "$d/out" 2>&1 && cmp -s "$d/out" tests/writer/layout.expected && echo "PASS layout (ada)" \
		  || { echo "FAIL layout (ada)"; grep -v warning "$d/cc.txt" 2>/dev/null | head -5; fail=$((fail+1)); }
	fi
}
layout

[ "$fail" -eq 0 ] && echo "writer OK" || { echo "writer: $fail FAIL"; exit 1; }
