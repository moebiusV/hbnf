#!/bin/sh
# Layout targets (LAYOUT.md): --target=NAME turns the bit rules into charts and renders a directory of transforms.
# Byte fixtures for the SVG target and the expression tags, determinism, the real pdp64 grammars' chart counts, and
# the promise that an annotation changes nothing the code backends generate.
#   HBNF=/path/to/hbnf sh tests/target.sh      (default ./hbnf)
set -u
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# check NAME GRAMMAR TARGETDIR EXPECTED [flags]: the stream a target writes to standard output is the fixture.
check() {
	n=$1; g=$2; td=$3; want=$4; shift 4
	"$CLI" "$g" --target="$td" --templates="$HBNF_TEMPLATES" "$@" > "$T/$n.out" 2> "$T/$n.err" || { bad "$n: $(cat "$T/$n.err")"; return; }
	[ -z "${TARGET_UPDATE:-}" ] || cp "$T/$n.out" "$want"
	if cmp -s "$T/$n.out" "$want"; then ok "$n"; else bad "$n: output differs"; diff "$T/$n.out" "$want" | head -10; fi
}

check mini-svg examples/mini.hbnf "$(pwd)/targets/svg" tests/target/mini-svg.expected
check expr examples/mini.hbnf "$(pwd)/tests/target/expr" tests/target/expr.expected

# the same run twice, and a run with --out: byte-stable, and the files are the stream
"$CLI" examples/mini.hbnf --target="$(pwd)/targets/svg" > "$T/a" 2>/dev/null
"$CLI" examples/mini.hbnf --target="$(pwd)/targets/svg" > "$T/b" 2>/dev/null
cmp -s "$T/a" "$T/b" && ok "deterministic" || bad "deterministic"
"$CLI" examples/mini.hbnf --target="$(pwd)/targets/svg" --out="$T/o" 2>/dev/null
[ -f "$T/o/leaf-LDB28.svg" ] && [ -f "$T/o/index.html" ] && ok "--out writes the files" || bad "--out writes the files"

# the real grammars: a chart for every leaf (pdp64/16: 270, pdp64/32: 268) and every alternative of the r20 body (21)
count() {
	n=$(HBNF_TEMPLATES=$HBNF_TEMPLATES "$CLI" "$1" --target="$(pwd)/targets/svg" 2>"$T/err" | grep -c '^%%% .*\.svg$')
	[ "$n" = "$2" ] && ok "$3: $n charts" || bad "$3: $n charts, want $2: $(head -2 "$T/err")"
}
count examples/pdp64/pdp64-16/pdp64-16.hbnf 270 pdp64/16
count examples/pdp64/pdp64-32/pdp64-32.hbnf 268 pdp64/32
count examples/pdp64/r20/pdp64.hbnf 21 r20

# an annotation changes nothing the code backends generate
sed -E 's/ %[a-z-]+\(("[^"]*" ?)+\)//g; s/ %(prefix)\b//g' examples/mini.hbnf > "$T/plain.hbnf"
for b in c rust zig ada; do
	"$CLI" examples/mini.hbnf --backend=$b > "$T/ann.$b" 2>&1
	"$CLI" "$T/plain.hbnf" --backend=$b > "$T/plain.$b" 2>&1
	if grep -v '^;' "$T/plain.hbnf" | grep -q '%'; then bad "annotations stripped"; break; fi
	cmp -s "$T/ann.$b" "$T/plain.$b" && ok "annotations do not change --backend=$b" || bad "annotations change --backend=$b"
done

# errors say what is wrong
printf 'prefix none\nr = a:4 %%reg(4)\n' > "$T/e1.hbnf"
"$CLI" "$T/e1.hbnf" --target="$(pwd)/targets/svg" > /dev/null 2> "$T/e1.err"
grep -q 'takes a string' "$T/e1.err" && ok "a role needs a string" || bad "a role needs a string: $(cat "$T/e1.err")"
"$CLI" examples/mini.hbnf --target=nosuch > /dev/null 2> "$T/e2.err"
grep -q 'no target directory' "$T/e2.err" && ok "an unknown target" || bad "an unknown target: $(cat "$T/e2.err")"
"$CLI" examples/mini.hbnf --target="$(pwd)/targets/svg" --chart-root=nope > /dev/null 2> "$T/e3.err"
grep -q 'no bit rule' "$T/e3.err" && ok "an unknown root" || bad "an unknown root: $(cat "$T/e3.err")"

[ "$fail" = 0 ] && echo "target: OK" || { echo "target: $fail failed"; exit 1; }
