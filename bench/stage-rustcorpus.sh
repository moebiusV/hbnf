#!/bin/sh
# stage-rustcorpus.sh -- the Rust parser on the repository's own corpora, three ways: as it was before
# its errors were made lazy and its nodes compact (bench/pre/ holds the two templates of that day,
# --no-compact), with lazy errors only (--no-compact), and as it is now (the default).  The files are
# each corpus's good files the Rust parser reads (a probe run drops the rest: the daemons' scanners
# written in C are not read by Rust).  Same generator, same grammar, same files.
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
out=$RESULTS/corpus_rust.md
cd /w
command -v rustc > /dev/null 2>&1 || { printf '| Rust | | skipped: no rustc | | | | | |\n' > "$out"; exit 0; }

# the templates as they were: a copy of templates/ with the two Rust parser templates of that day
cp -r /w/templates "$W/old-templates"
cp "$here/pre/rust_parser.tmpl" "$here/pre/rust_parse_text.tmpl" "$W/old-templates/"

build() {   # build NAME VARIANT TEMPLATES FLAG GRAMMAR
	d=$W/$1-$2; mkdir -p "$d"
	HBNF_TEMPLATES=$3 "$HBNF" "$5" --backend=rust $4 > "$d/$1.rs" 2> "$d/err" || return 1
	sed "s/MODULE/$1/g" "$here/corpus/main.rs" > "$d/m.rs"
	(cd "$d" && rustc --edition 2021 -C opt-level=3 -A warnings -o m m.rs > rc.txt 2>&1)
}

row() {   # row NAME GRAMMAR FILE...
	name=$1; g=$2; shift 2
	build "$name" before "$W/old-templates" --no-compact "$g" || { printf '| %s | | generate or rustc failed (before) | | | | | |\n' "$name"; return; }
	build "$name" lazy /w/templates --no-compact "$g" || { printf '| %s | | failed (lazy) | | | | | |\n' "$name"; return; }
	build "$name" now /w/templates "" "$g" || { printf '| %s | | failed (now) | | | | | |\n' "$name"; return; }
	good=""
	for f in "$@"; do "$W/$name-now/m" 1 "$f" > /dev/null 2>&1 && good="$good $f"; done
	[ -n "$good" ] || { printf '| %s | | no file parses | | | | | |\n' "$name"; return; }
	bytes=0; nf=0
	for f in $good; do bytes=$((bytes + $(wc -c < "$f"))); nf=$((nf + 1)); done
	reps=$((3000000 / (bytes > 0 ? bytes : 1))); [ $reps -lt 1 ] && reps=1; [ $reps -gt 20000 ] && reps=20000
	b=""; l=""; n=""; i=0
	while [ $i -lt 5 ]; do
		x=$(best_of 1 "$W/$name-before/m" $reps $good) || { printf '| %s | | run failed (before) | | | | | |\n' "$name"; return; }
		y=$(best_of 1 "$W/$name-lazy/m" $reps $good) || { printf '| %s | | run failed (lazy) | | | | | |\n' "$name"; return; }
		z=$(best_of 1 "$W/$name-now/m" $reps $good) || { printf '| %s | | run failed (now) | | | | | |\n' "$name"; return; }
		for v in b:x l:y n:z; do
			var=${v%%:*}; src=${v##*:}
			eval "cur=\$$var; new=\$$src"
			if [ -z "$cur" ] || awk -v p="${new%% *}" -v q="${cur%% *}" 'BEGIN{exit !(p<q)}'; then eval "$var=\$new"; fi
		done
		i=$((i + 1))
	done
	set -- $b; bms=$1; brss=$2
	set -- $l; lms=$1; lrss=$2
	set -- $n; nms=$1; nrss=$2
	awk -v name="$name" -v nf="$nf" -v reps="$reps" -v by="$((bytes * reps))" -v a="$bms" -v b="$lms" -v c="$nms" -v r1="$lrss" -v r2="$nrss" 'BEGIN {
		printf "| %s | %d files x %d | %.1f MB | %.0f ms | %.0f ms | %.0f ms | %.1fx | %.0f MB | %.0f MB |\n",
		  name, nf, reps, by / 1e6, a, b, c, a / c, r1 / 1024, r2 / 1024 }'
}

{
	printf '| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |\n'
	printf '|---|---|---:|---:|---:|---:|---:|---:|---:|\n'
	row json corpus/json/json.hbnf corpus/json/tests/good/*.json
	row mustache corpus/mustache/mustache.hbnf corpus/mustache/tests/good/*.mustache
	row algol60 corpus/algol60/algol60.hbnf corpus/algol60/tests/good/*.a60
	for d in httpd relayd snmpd; do
		row "$d" "grammars/obconf_$d.hbnf" tests/daemons/$d/*.conf
	done
	printf '\n'
	[ -f "$RESULTS/env.md" ] && printf '_%s_\n' "$(cat "$RESULTS/env.md")"
} > "$out"
