#!/bin/sh
# `layout tape` (RFCPLAN.md step 17): a plain grammar, with no %emit in it, makes a parser that writes a
# flat tape instead of building the tree.  (1) The exact tape of a small JSON document.  (2) The tape of
# every good JSON document of the corpus has the objects, arrays, members, strings, numbers and literals
# Python finds, and the bad ones are refused.  (3) TOML and YAML: the tape parsers accept and refuse what
# the plain ones do (tests/toml-diff.sh against tomllib; the YAML test suite).  (4) The directive in a
# grammar, and --layout= with something else, are read as they should be.  (5) `layout tailq`.
#   HBNF=/path/to/hbnf sh tests/layout.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0

"$CLI" corpus/json/json.hbnf --backend=c --layout=tape > "$W/j.c" 2> "$W/j.err" \
	|| { echo "layout: FAIL (json: $(head -c 300 "$W/j.err"))"; fail=1; }
cat "$W/j.c" tests/layout/dump.c > "$W/jm.c"
${CC:-cc} -O1 -std=gnu11 -w -D_GNU_SOURCE -Iruntime -DOUT_T=json_t -o "$W/j" "$W/jm.c" 2> "$W/cc.err" \
	|| { echo "layout: FAIL (json does not compile: $(head -c 300 "$W/cc.err"))"; fail=1; }
if [ -x "$W/j" ]; then
	"$W/j" tests/layout/small.json > "$W/small.out"
	cmp -s "$W/small.out" tests/layout/small.expected \
		|| { echo "layout: FAIL (the tape of small.json is not the expected one)"; diff "$W/small.out" tests/layout/small.expected | head -6; fail=1; }
	python3 tests/layout/json-counts.py corpus/json/tests "$W/j" > "$W/counts.out" 2>&1 \
		|| { echo "layout: FAIL (json counts: $(head -c 300 "$W/counts.out"))"; fail=1; }
fi

# YAML: the exact tape of a small document (the `flat` rules write no node, the blanks and quotes are hidden,
# a scalar over several lines is one entry), as the hand-written tape has it
"$CLI" corpus/yaml/yaml.hbnf --backend=c --root=yaml --layout=tape > "$W/y.c" 2> "$W/y.err" \
	|| { echo "layout: FAIL (yaml: $(head -c 300 "$W/y.err"))"; fail=1; }
cat "$W/y.c" tests/layout/dump.c > "$W/ym.c"
${CC:-cc} -O1 -std=gnu11 -w -D_GNU_SOURCE -Iruntime -DOUT_T=yaml_t -o "$W/yd" "$W/ym.c" 2> "$W/cc.err" \
	|| { echo "layout: FAIL (yaml does not compile: $(head -c 300 "$W/cc.err"))"; fail=1; }
if [ -x "$W/yd" ]; then
	"$W/yd" tests/layout/small.yaml > "$W/small-yaml.out"
	cmp -s "$W/small-yaml.out" tests/layout/small-yaml.expected \
		|| { echo "layout: FAIL (the tape of small.yaml is not the expected one)"; diff "$W/small-yaml.out" tests/layout/small-yaml.expected | head -6; fail=1; }
fi

HBNF_FLAGS=--layout=tape HBNF="$CLI" sh tests/toml-diff.sh 300 1 > "$W/toml.out" 2>&1 \
	|| { echo "layout: FAIL (toml: $(tail -2 "$W/toml.out" | head -c 300))"; fail=1; }
Y=${YAML_TEST_SUITE:-bench/cache/yaml-test-suite}
if [ -d "$Y" ]; then
	HBNF_FLAGS=--layout=tape YAML_TEST_SUITE="$Y" HBNF="$CLI" sh tests/yaml-suite.sh > "$W/yaml.out" 2>&1 \
		|| { echo "layout: FAIL (yaml: $(tail -2 "$W/yaml.out" | head -c 300))"; fail=1; }
fi

# the directive in a grammar does what the flag does; a layout that is not one is refused
printf 'layout tape\nprefix none\nwhitespace none\ntop = "(" *( top ) ")"\n' > "$W/d.hbnf"
"$CLI" "$W/d.hbnf" --backend=c 2> "$W/d.err" | grep -q 'tape_open' \
	|| { echo "layout: FAIL (the layout directive does not make a tape)"; fail=1; }
"$CLI" "$W/d.hbnf" --backend=c --layout=ast 2> "$W/d.err" | grep -q 'tape_open' \
	&& { echo "layout: FAIL (--layout=ast does not win over the directive)"; fail=1; }
# layout tailq is a directory of layouts/ (layouts/tailq/layout.hbnf): its operations and its prologue.
# The directive and the flag make the same parser, it makes TAILQ lists and compiles against <sys/queue.h>
# (tests/bsdinc stands in where the libc has none), and a grammar's own layout_ops specialises it
"$CLI" tests/layout/tailq.hbnf --backend=c > "$W/tl.c" 2> "$W/tl.err" \
	&& "$CLI" tests/layout/tailq-plain.hbnf --backend=c --layout=tailq > "$W/tf.c" 2> "$W/tf.err" \
	|| { echo "layout: FAIL (tailq: $(head -c 300 "$W/tl.err" "$W/tf.err"))"; fail=1; }
cmp -s "$W/tl.c" "$W/tf.c" || { echo "layout: FAIL (layout tailq and --layout=tailq make different parsers)"; fail=1; }
grep -q 'TAILQ_INSERT_TAIL' "$W/tl.c" || { echo "layout: FAIL (layout tailq does not make TAILQ lists)"; fail=1; }
${CC:-cc} -std=gnu11 -w -Itests/bsdinc -c -o "$W/tl.o" "$W/tl.c" 2> "$W/cc.err" \
	|| { echo "layout: FAIL (tailq does not compile: $(head -c 300 "$W/cc.err"))"; fail=1; }
"$CLI" tests/layout/tailq-special.hbnf --backend=c > "$W/ts.c" 2> "$W/ts.err" \
	|| { echo "layout: FAIL (tailq special: $(head -c 300 "$W/ts.err"))"; fail=1; }
grep -q 'MYINIT' "$W/ts.c" && ! grep -q 'TAILQ_INIT(&head)' "$W/ts.c" && grep -q 'TAILQ_INSERT_TAIL' "$W/ts.c" \
	|| { echo "layout: FAIL (a grammar's layout_ops does not specialise layout tailq)"; fail=1; }
printf 'prefix none\nlayout nonesuch\ntop = "a"\n' > "$W/n.hbnf"
"$CLI" "$W/n.hbnf" --backend=c 2>&1 >/dev/null | grep -q 'no file nonesuch/layout.hbnf' \
	|| { echo "layout: FAIL (an unknown layout is not refused with the file it wanted)"; fail=1; }
[ $fail = 0 ] && echo "layout: OK (a tape from the plain grammars of JSON, TOML and YAML; tailq)"
exit $fail
