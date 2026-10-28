#!/bin/sh
# inner.sh -- inside one of the two containers (musl or glibc): build every driver and the hbnf
# parsers, time each on its document, print one TSV row each: FORMAT LABEL MS RSS_KIB STATUS.
# /w is the repository (read-only), /o the work directory holding doc.{json,toml,yaml} and the
# generated {json,toml,yaml}.c.
set -u
RUNS=${RUNS:-5}
L=/w/bench/libs
cd /o
export CARGO_HOME=/o/cargo-home HOME=/tmp
CC="gcc -O2 -w"; CXX="g++ -O2 -w -std=c++20"
cp /w/bench/cache/libs/* /o/ 2> /dev/null

best() {   # best FORMAT LABEL DOC CMD...: least parse time of RUNS runs
	fmt=$1; label=$2; doc=$3; shift 3
	i=0; bm=""; br=""; st=ok
	while [ $i -lt $RUNS ]; do
		out=$("$@" "$doc" 2> /o/err.txt | tail -1)
		case $out in ok*) ;; *) st="refused: $(head -c 80 /o/err.txt | tr '\n\t' '  ')"; break ;; esac
		ms=$(echo "$out" | awk '{print $3}'); rss=$(echo "$out" | awk '{print $4}')
		if [ -z "$bm" ] || awk -v a="$ms" -v b="$bm" 'BEGIN{exit !(a<b)}'; then bm=$ms; br=$rss; fi
		i=$((i + 1))
	done
	printf '%s\t%s\t%s\t%s\t%s\n' "$fmt" "$label" "${bm:-0}" "${br:-0}" "$st"
}
try() {   # try FORMAT LABEL DOC SRC FLAGS...: compile, then time
	fmt=$1; label=$2; doc=$3; src=$4; shift 4
	exe=/o/bin-$(basename "$src" | tr . _)
	case $src in *.cpp) cc="$CXX" ;; *) cc="$CC" ;; esac
	if $cc -I"$L" -I/o "$L/$src" -o "$exe" "$@" 2> /o/cc.txt; then best "$fmt" "$label" "$doc" "$exe"
	else printf '%s\t%s\t0\t0\tbuild failed: %s\n' "$fmt" "$label" "$(grep -m1 error /o/cc.txt | head -c 80)"; fi
}

for n in json toml yaml; do
	t=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' /o/$n.c)
	cat /o/$n.c /w/bench/formats/time_format.c > /o/$n-m.c
	$CC -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$t" /o/$n-m.c -o /o/bin-hbnf-$n 2> /dev/null
	best $n "hbnf (C backend), typed tree" /o/doc.$n /o/bin-hbnf-$n
done
# JSON again, read onto a flat tape by %emit with no tree (corpus/json/json-tape.hbnf)
t=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' /o/json-tape.c)
cat /o/json-tape.c /w/bench/formats/time_tape.c > /o/json-tape-m.c
$CC -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$t" /o/json-tape-m.c -o /o/bin-hbnf-json-tape 2> /dev/null
best json "hbnf (C backend), %emit tape" /o/doc.json /o/bin-hbnf-json-tape

try json cJSON      /o/doc.json cjson.c -lcjson
try json Jansson    /o/doc.json jansson.c -ljansson
try json RapidJSON  /o/doc.json rapidjson.cpp
try json "simdjson (DOM)" /o/doc.json simdjson.cpp -lsimdjson
try toml "toml++"   /o/doc.toml tomlpp.cpp
try toml toml11     /o/doc.toml toml11.cpp
try toml tomlc17    /o/doc.toml tomlc17.c /o/tomlc17.c
try yaml libyaml    /o/doc.yaml libyaml.c -lyaml
try yaml libfyaml   /o/doc.yaml libfyaml.c -lfyaml
try yaml yaml-cpp   /o/doc.yaml yamlcpp.cpp -lyaml-cpp
try yaml rapidyaml  /o/doc.yaml ryml.cpp

cp -r $L/rust /o/rust
if (cd /o/rust && CARGO_TARGET_DIR=/o/rust-target cargo build -q --release 2> /o/cargo.txt); then
	best json "serde_json (Rust)" /o/doc.json /o/rust-target/release/libs-rust serde_json
	best toml "toml (Rust)" /o/doc.toml /o/rust-target/release/libs-rust toml
else printf 'json\tserde_json (Rust)\t0\t0\tbuild failed: %s\n' "$(grep -m1 error /o/cargo.txt | head -c 80)"; fi

# the parsers of the scripting languages, as their programs use them
best json "Python json" /o/doc.json python3 /w/bench/formats/time_py.py json
best json "Node JSON.parse" /o/doc.json node /w/bench/formats/time_node.js
best toml "Python tomllib" /o/doc.toml python3 /w/bench/formats/time_py.py tomllib
best yaml "PyYAML on libyaml (C)" /o/doc.yaml python3 /w/bench/formats/time_py.py yaml-c
best yaml "js-yaml (Node)" /o/doc.yaml node /w/bench/libs/time_jsyaml.js
