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

[ "$fail" -eq 0 ] && echo "writer OK" || { echo "writer: $fail FAIL"; exit 1; }
