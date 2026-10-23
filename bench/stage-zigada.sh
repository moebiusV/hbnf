#!/bin/sh
# stage-zigada.sh -- the Zig and Ada parsers on the repository's own corpora.
#   Zig: as it was (a generator built from bench/pre/: eager error messages, merged structs), with the
#   errors made lazy only (--no-compact), and as it is now (compact nodes, the default).
#   Ada: the generator and templates of that day (it raised an exception for every failed
#   alternative) against today's (a failure is a flag on the parser).
# Same grammar, same files; the files are each corpus's good files the parser reads (a probe run drops
# the rest).  The time is CPU time for Zig (std has no clock to read) and wall time for Ada.
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cd /w
zout=$RESULTS/corpus_zig.md; aout=$RESULTS/corpus_ada.md

# the generator as it was, built once and kept (cache/hbnf-pre-<hash of the three files>)
sum=$(cat "$here/pre/hbnf_zig.adb" "$here/pre/hbnf_zig.ads" "$here/pre/hbnf.adb" "$here/pre/hbnf_ada.adb" "$here/pre/hbnf_wire-ada_lang.adb" | sha256sum | cut -c1-12)
PRE=$here/cache/hbnf-pre-$sum
if [ ! -x "$PRE" ] && command -v gnatmake > /dev/null 2>&1; then
	mkdir -p "$W/pre"
	cp /w/*.ad[sb] "$W/pre/"
	cp "$here/pre/hbnf_zig.adb" "$here/pre/hbnf_zig.ads" "$here/pre/hbnf.adb" "$here/pre/hbnf_ada.adb" "$here/pre/hbnf_wire-ada_lang.adb" "$W/pre/"
	(cd "$W/pre" && gnatmake -q -gnat2022 -gnatws -I. -I/usr/include/mustache hbnf.adb -o hbnf-pre > build.log 2>&1) \
		&& { mkdir -p "$here/cache"; cp "$W/pre/hbnf-pre" "$PRE"; }
fi
cp -r /w/templates "$W/old-templates"
cp "$here/pre/ada_parser_prims.tmpl" "$here/pre/ada_parse_text.tmpl" "$W/old-templates/"

zig_build() {   # zig_build DIR NAME GENERATOR FLAG GRAMMAR REPS FILE...
	d=$1; n=$2; gen=$3; flag=$4; g=$5; reps=$6; shift 6
	mkdir -p "$d"
	"$gen" "$g" --backend=zig $flag > "$d/$n.zig" 2> "$d/err" || return 1
	: > "$d/files.txt"; i=0
	for f in "$@"; do
		i=$((i + 1)); cp "$f" "$d/f$i.dat"
		printf '    .{ .name = "%s", .data = @embedFile("f%d.dat") },\n' "$f" "$i" >> "$d/files.txt"
	done
	sed "s/MODULE/$n.zig/g; s/REPS/$reps/g" "$here/corpus/main.zig" \
	  | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	(cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1)
}
zig_run() { ( cd "$1" && ./m 2>&1 | tail -1 ); }   # the driver reports on stderr

zrow() {   # zrow NAME GRAMMAR REPS FILE...
	name=$1; g=$2; reps=$3; shift 3
	good="$*"
	zig_build "$W/z-$name-b" "$name" "${PRE:-$HBNF}" "" "$g" "$reps" $good || { printf '| %s | | zig failed (before) | | | | | |\n' "$name"; return; }
	zig_build "$W/z-$name-l" "$name" "$HBNF" --no-compact "$g" "$reps" $good || { printf '| %s | | zig failed (lazy) | | | | | |\n' "$name"; return; }
	zig_build "$W/z-$name-n" "$name" "$HBNF" "" "$g" "$reps" $good || { printf '| %s | | zig failed (now) | | | | | |\n' "$name"; return; }
	b=""; l=""; n=""; i=0
	while [ $i -lt 5 ]; do
		for v in b l n; do
			cur=$(zig_run "$W/z-$name-$v" | awk '$1 == "ok" { print $5, $6 }')
			[ -n "$cur" ] || { printf '| %s | | run failed (%s) | | | | | |\n' "$name" "$v"; return; }
			eval "old=\$$v"
			if [ -z "$old" ] || awk -v p="${cur%% *}" -v q="${old%% *}" 'BEGIN{exit !(p<q)}'; then eval "$v=\$cur"; fi
		done
		i=$((i + 1))
	done
	set -- $b; bms=$1
	set -- $l; lms=$1; lrss=$2
	set -- $n; nms=$1; nrss=$2
	info=$(zig_run "$W/z-$name-n"); nf=$(echo "$info" | awk '{print $4}'); bytes=$(echo "$info" | awk -v r="$reps" '{print $2 / r}')
	awk -v name="$name" -v nf="$nf" -v reps="$reps" -v by="$((bytes * reps))" -v a="$bms" -v b="$lms" -v c="$nms" -v r1="$lrss" -v r2="$nrss" 'BEGIN {
		printf "| %s | %d files x %d | %.1f MB | %.0f ms | %.0f ms | %.0f ms | %.1fx | %.0f MB | %.0f MB |\n",
		  name, nf, reps, by / 1e6, a, b, c, a / c, r1 / 1024, r2 / 1024 }'
}

{
	printf '| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |\n'
	printf '|---|---|---:|---:|---:|---:|---:|---:|---:|\n'
	if command -v zig > /dev/null 2>&1 && [ -x "$PRE" ]; then
		zrow json corpus/json/json.hbnf 3000 corpus/json/tests/good/*.json
		zrow mustache corpus/mustache/mustache.hbnf 3000 corpus/mustache/tests/good/*.mustache
		zrow algol60 corpus/algol60/algol60.hbnf 1000 corpus/algol60/tests/good/*.a60
		zrow httpd grammars/obconf_httpd.hbnf 2000 tests/daemons/httpd/*.conf
		zrow relayd grammars/obconf_relayd.hbnf 2000 tests/daemons/relayd/*.conf
	else
		printf '| Zig | | skipped: no zig or no pre-change generator | | | | | | |\n'
	fi
	printf '\n'
	[ -f "$RESULTS/env.md" ] && printf '_%s_\n' "$(cat "$RESULTS/env.md")"
} > "$zout"

# ---- Ada ----
arow() {   # arow NAME GRAMMAR REPS FILE...
	name=$1; g=$2; reps=$3; shift 3
	for v in before now; do
		t=/w/templates; gen=$HBNF
		[ $v = before ] && { t=$W/old-templates; gen=${PRE:-$HBNF}; }
		d=$W/a-$name-$v; mkdir -p "$d"
		HBNF_TEMPLATES=$t "$gen" "$g" --backend=ada --package=Bn > "$d/all.ada" 2> "$d/err" || { printf '| %s | | generate failed | | | |\n' "$name"; return; }
		root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
		sed "s/MODULE/Bn/g; s/ROOT/$root/g" "$here/corpus/main.adb" > "$d/main.adb"
		(cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws main.adb -o m > cc.txt 2>&1) \
			|| { printf '| %s | | gnat failed (%s) | | | |\n' "$name" "$v"; return; }
	done
	good=""
	for f in "$@"; do "$W/a-$name-now/m" 1 "$f" > /dev/null 2>&1 && good="$good $f"; done
	[ -n "$good" ] || { printf '| %s | | no file parses | | | |\n' "$name"; return; }
	bytes=0; nf=0
	for f in $good; do bytes=$((bytes + $(wc -c < "$f"))); nf=$((nf + 1)); done
	b=""; n=""; i=0
	while [ $i -lt 5 ]; do
		x=$(best_of 1 "$W/a-$name-before/m" $reps $good) || return
		y=$(best_of 1 "$W/a-$name-now/m" $reps $good) || return
		if [ -z "$b" ] || awk -v p="${x%% *}" -v q="${b%% *}" 'BEGIN{exit !(p<q)}'; then b=$x; fi
		if [ -z "$n" ] || awk -v p="${y%% *}" -v q="${n%% *}" 'BEGIN{exit !(p<q)}'; then n=$y; fi
		i=$((i + 1))
	done
	set -- $b; bms=$1
	set -- $n; nms=$1; nrss=$2
	awk -v name="$name" -v nf="$nf" -v reps="$reps" -v by="$((bytes * reps))" -v a="$bms" -v c="$nms" -v r="$nrss" 'BEGIN {
		printf "| %s | %d files x %d | %.1f MB | %.0f ms | %.0f ms | %.2fx | %.0f MB |\n", name, nf, reps, by / 1e6, a, c, a / c, r / 1024 }'
}
{
	printf '| corpus | input | parsed | time before (exceptions) | time now | faster | memory |\n'
	printf '|---|---|---:|---:|---:|---:|---:|\n'
	if command -v gnatmake > /dev/null 2>&1; then
		arow json corpus/json/json.hbnf 300 corpus/json/tests/good/*.json
		arow mustache corpus/mustache/mustache.hbnf 300 corpus/mustache/tests/good/*.mustache
		arow httpd grammars/obconf_httpd.hbnf 200 tests/daemons/httpd/*.conf
		arow relayd grammars/obconf_relayd.hbnf 200 tests/daemons/relayd/*.conf
	else
		printf '| Ada | | skipped: no gnatmake | | | | |\n'
	fi
	printf '\n'
	[ -f "$RESULTS/env.md" ] && printf '_%s_\n' "$(cat "$RESULTS/env.md")"
} > "$aout"
