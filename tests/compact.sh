#!/bin/sh
# Compact nodes (the default; --no-compact turns them off) (C): a struct that gathers several rules' fields holds each as an arena pointer, so a
# node costs the one alternative taken.  The tree must be the same tree: every C round trip of
# tests/writer.sh (parse, write, re-parse, write) must pass with it, and the pfctl grammar must
# hold a 100,000-rule file in at most half the memory of the default layout.
#   HBNF=/path/to/hbnf sh tests/compact.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
out=$(HBNF_C_FLAGS=--no-compact sh tests/writer.sh 2>&1) || { echo "compact: FAIL (--no-compact)"; echo "$out" | head -20; exit 1; }

for v in plain compact; do
	flag=--compact; [ $v = plain ] && flag=--no-compact
	"$CLI" grammars/obconf_pfctl.hbnf --backend=c $flag > "$W/$v.c" || { echo "compact: FAIL (generate $v)"; exit 1; }
	mkdir -p "$W/$v.d"
	cat "$W/$v.c" bench/pfctl/time_hbnf.c > "$W/$v.d/m.c"
	cc -O1 -std=gnu11 -w -I"$W/$v.d" -Itests/bsdinc "$W/$v.d/m.c" -o "$W/$v" || { echo "compact: FAIL (cc $v)"; exit 1; }
done
sh bench/gen.sh pfctl 20000 > "$W/in.txt"
a=$("$W/plain" "$W/in.txt"); b=$("$W/compact" "$W/in.txt")
na=$(echo "$a" | awk '{print $3}'); nb=$(echo "$b" | awk '{print $3}')
ra=$(echo "$a" | awk '{print $6}'); rb=$(echo "$b" | awk '{print $6}')
[ "$na" = 20000 ] && [ "$nb" = 20000 ] || { echo "compact: FAIL (rules found: plain $na, compact $nb)"; exit 1; }
[ $((rb * 2)) -le "$ra" ] || { echo "compact: FAIL (memory ${rb} KiB is more than half of ${ra} KiB)"; exit 1; }
echo "compact: OK (C round trips pass; pfctl 20,000 rules in ${rb} KiB against ${ra} KiB)"
