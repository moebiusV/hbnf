#!/bin/sh
# stage-formats.sh -- JSON, TOML and YAML: the parser hbnf makes from each shipped grammar
# (corpus/json, corpus/toml, corpus/yaml; the C backend) against the usual libraries for the format,
# on one generated document each (bench/formats/gen.py), a list of records with strings,
# numbers, booleans, lists and a nested table.
#
# What each side builds is not the same, and the table says so: hbnf builds the typed tree its
# grammar describes (each string is a slice of the input); the libraries build the host language's own
# objects (Python dicts and lists, JavaScript values), which is more work and what a program wants
# to hold.  So this is "the parser and its tree" against "the library as it is".
. "$here/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
out=$RESULTS/formats.md
FMT_BYTES=${FMT_BYTES:-2000000}
fmt=$here/formats

fmt_row() {   # fmt_row LABEL FILE CMD...
	label=$1; file=$2; shift 2
	bytes=$(wc -c < "$file")
	got=$(best_of_simple "$RUNS" "$@") || { printf '| %s | | run failed | | |\n' "$label"; return; }
	set -- $got
	awk -v l="$label" -v b="$bytes" -v ms="$1" -v rss="$2" 'BEGIN {
		printf "| %s | %s | %.0f MB/s | %.0f MB |\n", l,
		  (ms < 10 ? sprintf("%.1f ms", ms) : ms < 1000 ? sprintf("%.0f ms", ms) : sprintf("%.2f s", ms/1000)),
		  b / 1e6 / (ms / 1000), rss / 1024
	}'
	mkdir -p "$RESULTS/vals"
	awk -v k="$KEY" -v ms="$1" -v b="$bytes" 'BEGIN { printf "fmt_%s_ms=%.0f\nfmt_%s_mbs=%.0f\n", k, ms, k, b / 1e6 / (ms / 1000) }' >> "$RESULTS/vals/formats.txt"
}

build_hbnf() {   # build_hbnf NAME ROOT
	name=$1; root=$2
	"$HBNF" /w/corpus/$name/$name.hbnf --backend=c --root=$root > "$W/$name.c" 2> "$W/$name.err" || return 1
	t=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$name.c")
	cat "$W/$name.c" "$fmt/time_format.c" > "$W/$name-m.c"
	gcc -O2 -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$t" "$W/$name-m.c" -o "$W/$name-hbnf" 2> "$W/$name.cc"
}

rm -f "$RESULTS/vals/formats.txt"
{
	for spec in "json:JSON:json" "toml:TOML 1.0:toml" "yaml:YAML 1.2:yaml"; do
		name=${spec%%:*}; rest=${spec#*:}; title=${rest%%:*}; root=${rest##*:}
		python3 "$fmt/gen.py" "$name" "$FMT_BYTES" > "$W/doc.$name"
		bytes=$(wc -c < "$W/doc.$name")
		printf '**%s** (%s MB, the same file for every tool):\n\n' "$title" "$(awk -v b="$bytes" 'BEGIN{printf "%.2f", b/1e6}')"
		printf '| tool | parse time | MB/s | peak RSS |\n|---|---:|---:|---:|\n'
		KEY=${name}_hbnf
		if build_hbnf "$name" "$root"; then
			fmt_row "hbnf (C backend), typed tree" "$W/doc.$name" "$W/$name-hbnf" "$W/doc.$name"
		else
			printf '| hbnf (C backend) | skipped: %s | | |\n' "$(grep -m1 -E 'error|hbnf:' "$W/$name.err" "$W/$name.cc" | cut -c1-100)"
		fi
		case $name in
		json)
			KEY=json_python;  fmt_row "Python $(python3 -c 'import platform;print(platform.python_version())') json" "$W/doc.json" python3 "$fmt/time_py.py" json "$W/doc.json"
			KEY=json_node;    fmt_row "Node $(node --version | tr -d v) JSON.parse" "$W/doc.json" node "$fmt/time_node.js" "$W/doc.json" ;;
		toml)
			KEY=toml_python;  fmt_row "Python tomllib" "$W/doc.toml" python3 "$fmt/time_py.py" tomllib "$W/doc.toml" ;;
		yaml)
			KEY=yaml_libyaml; fmt_row "PyYAML $(python3 -c 'import yaml;print(yaml.__version__)') on libyaml (C)" "$W/doc.yaml" python3 "$fmt/time_py.py" yaml-c "$W/doc.yaml"
			KEY=yaml_python;  fmt_row "PyYAML, pure Python" "$W/doc.yaml" python3 "$fmt/time_py.py" yaml-py "$W/doc.yaml" ;;
		esac
		printf '\n'
	done
	[ -f "$RESULTS/env.md" ] && printf '_%s_\n' "$(cat "$RESULTS/env.md")"
} > "$out"
