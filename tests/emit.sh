#!/bin/sh
# The type after `::` and the `%emit` block (RFCPLAN.md step 15), as far as the reader goes:
# `name :: type = ...` is read for one word, several words and a parameterised rule; a head with no
# type, or no `=`, is refused with the form it wants; `%emit` is read between elements and at the
# end of a rule, and a grammar that uses it is refused by rule name until a backend generates it.
#   HBNF=/path/to/hbnf sh tests/emit.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
for f in plain typed; do
	"$CLI" tests/emit/$f.hbnf --backend=c > "$W/$f.c" 2> "$W/$f.err" \
		|| { echo "emit: FAIL ($f: $(head -c 200 "$W/$f.err"))"; fail=1; }
done
for f in no-type no-eq; do
	"$CLI" tests/emit/$f.hbnf --backend=c 2>&1 > /dev/null | grep -q 'expected `name :: type =`' \
		|| { echo "emit: FAIL ($f: not refused with the form it wants)"; fail=1; }
done
# a grammar whose choices are all told apart gets past the analysis and is generated
for f in read safe unrelated emit-last prefix-lits; do
	"$CLI" tests/emit/$f.hbnf --backend=c > "$W/$f.c" 2> "$W/$f.err" \
		|| { echo "emit: FAIL ($f: $(head -c 200 "$W/$f.err"))"; fail=1; }
done
for b in rust zig; do
	"$CLI" tests/emit/safe.hbnf --backend=$b 2>&1 > /dev/null | grep -q 'has an %emit, which only the C and Ada backends generate so far' \
		|| { echo "emit: FAIL (safe: $b does not refuse an %emit by name)"; fail=1; }
done
# the code of an %emit is the grammar's own: C here, so Ada says so (a file that says `language Ada` is generated, below)
"$CLI" tests/emit/safe.hbnf --backend=ada 2>&1 > /dev/null | grep -q 'which is code written in C' \
	|| { echo "emit: FAIL (safe: ada does not refuse C code in an %emit)"; fail=1; }
# the generated parser runs the emits in order, with `$$` and the elements as variables, and a
# parse that fails reports where without running them again
"$CLI" tests/emit/run.hbnf --backend=c > "$W/run.c" 2> "$W/run.err" \
	|| { echo "emit: FAIL (run: $(head -c 200 "$W/run.err"))"; fail=1; }
cat tests/emit/run.c >> "$W/run.c"
${CC:-cc} -std=gnu11 -w -o "$W/run" "$W/run.c" 2> "$W/cc.err" \
	|| { echo "emit: FAIL (run: does not compile: $(head -c 300 "$W/cc.err"))"; fail=1; }
if [ -x "$W/run" ]; then
	while read -r input want; do
		got=$("$W/run" "$input")
		[ "$got" = "$want" ] || { echo "emit: FAIL (run $input: got '$got', wanted '$want')"; fail=1; }
	done <<'CASES'
[] 0
[t] 1
[f] 0
[t,f,[t,t]] 3
[[[t]],[t,t],f] 3
[t,[] error 1:6
[t,x] error 1:4
CASES
fi
# alternatives that begin with the same elements read them once, and the emits of the shared part run once
# (the value, the depth of the stack and its sum: `rollback` puts the stack back for the alternative given up)
"$CLI" tests/emit/runs.hbnf --backend=c > "$W/runs.c" 2> "$W/runs.err" \
	|| { echo "emit: FAIL (runs: $(head -c 200 "$W/runs.err"))"; fail=1; }
grep -q 'pn[0-9]*_1_[0-9]*:' "$W/runs.c" && grep -q 'pn[0-9]*_2_[0-9]*:' "$W/runs.c" \
	|| { echo "emit: FAIL (runs: the shared beginning is not written out once, nor the one under it)"; fail=1; }
cat tests/emit/runs.c >> "$W/runs.c"
${CC:-cc} -std=gnu11 -w -o "$W/runs" "$W/runs.c" 2> "$W/cc.err" \
	|| { echo "emit: FAIL (runs: does not compile: $(head -c 300 "$W/cc.err"))"; fail=1; }
if [ -x "$W/runs" ]; then
	while IFS== read -r input want; do
		got=$("$W/runs" "$input")
		[ "$got" = "$want" ] || { echo "emit: FAIL (runs $input: got '$got', wanted '$want')"; fail=1; }
	done <<'CASES'
a(1)=1 3 103
b()=2 2 201
c(0)=1 3 103
c:a=3 3 302
a:b=3 3 302
a=4 2 401
a(=error 1:3
a(2)=error 1:3
d=error 1:1
b(1=error 1:4
CASES
fi
# JSON read onto a tape: the same counts of each kind as Python finds, in every good document, and
# every bad one refused
"$CLI" corpus/json/json-tape.hbnf --backend=c > "$W/jt.c" 2> "$W/jt.err" \
	|| { echo "emit: FAIL (json-tape: $(head -c 200 "$W/jt.err"))"; fail=1; }
cat tests/emit/json-tape.c >> "$W/jt.c"
${CC:-cc} -O1 -std=gnu11 -w -Iruntime -o "$W/jt" "$W/jt.c" 2> "$W/cc.err" \
	&& python3 tests/emit/json-tape.py corpus/json/tests "$W/jt" \
	|| { echo "emit: FAIL (json-tape: $(head -c 300 "$W/cc.err"))"; fail=1; }
# TOML read onto a tape: the same language as toml.hbnf (asked of tomllib about random documents and
# mutations of them), and the same strings, integers, floats, booleans and dates as tomllib finds in
# every good document of the corpus
TOML_GRAMMAR=corpus/toml/toml-tape.hbnf HBNF="$CLI" sh tests/toml-diff.sh 300 1 > "$W/tdiff.out" 2>&1 \
	|| { echo "emit: FAIL (toml-tape: toml-diff: $(tail -3 "$W/tdiff.out" | head -c 300))"; fail=1; }
"$CLI" corpus/toml/toml-tape.hbnf --backend=c > "$W/tt.c" 2> "$W/tt.err" \
	|| { echo "emit: FAIL (toml-tape: $(head -c 200 "$W/tt.err"))"; fail=1; }
cat tests/emit/toml-tape.c >> "$W/tt.c"
${CC:-cc} -O1 -std=gnu11 -w -Iruntime -o "$W/tt" "$W/tt.c" 2> "$W/cc.err" \
	&& python3 tests/emit/toml-tape.py corpus/toml/tests "$W/tt" \
	|| { echo "emit: FAIL (toml-tape: $(head -c 300 "$W/cc.err"))"; fail=1; }
# YAML read onto a tape: the same language as yaml.hbnf (the YAML test suite, valid and invalid cases) and
# the same structure (the tape read back as events has the suite's test.event for every case but
# those in corpus/yaml/tape-gaps.txt)
Y=${YAML_TEST_SUITE:-bench/cache/yaml-test-suite}
if [ -d "$Y" ]; then
	YAML_GRAMMAR=corpus/yaml/yaml-tape.hbnf YAML_TEST_SUITE="$Y" HBNF="$CLI" sh tests/yaml-suite.sh > "$W/ysuite.out" 2>&1 \
		|| { echo "emit: FAIL (yaml-tape: yaml-suite: $(tail -3 "$W/ysuite.out" | head -c 300))"; fail=1; }
	"$CLI" corpus/yaml/yaml-tape.hbnf --backend=c --root=yaml > "$W/yt.c" 2> "$W/yt.err" \
		|| { echo "emit: FAIL (yaml-tape: $(head -c 200 "$W/yt.err"))"; fail=1; }
	cat tests/emit/yaml-tape.c >> "$W/yt.c"
	${CC:-cc} -O1 -std=gnu11 -w -D_GNU_SOURCE -Iruntime -o "$W/yt" "$W/yt.c" 2> "$W/cc.err" \
		&& python3 tests/emit/yaml-tape.py "$Y" "$W/yt" corpus/yaml/suite-gaps.txt corpus/yaml/tape-gaps.txt > "$W/yt.out" \
		|| { echo "emit: FAIL (yaml-tape: $(tail -4 "$W/yt.out" "$W/cc.err" 2>/dev/null | head -c 400))"; fail=1; }
fi
# rollback { depth }: a retry puts back what the emits changed, so only the alternative that
# succeeds leaves its pushes; without the directive the same grammar is refused
"$CLI" tests/emit/rollback.hbnf --backend=c > "$W/rb.c" 2> "$W/rb.err" \
	|| { echo "emit: FAIL (rollback: $(head -c 200 "$W/rb.err"))"; fail=1; }
cat tests/emit/rollback.c >> "$W/rb.c"
${CC:-cc} -std=gnu11 -w -o "$W/rb" "$W/rb.c" 2> "$W/cc.err" \
	|| { echo "emit: FAIL (rollback: does not compile: $(head -c 300 "$W/cc.err"))"; fail=1; }
if [ -x "$W/rb" ]; then
	while read -r input want; do
		got=$("$W/rb" "$input")
		[ "$got" = "$want" ] || { echo "emit: FAIL (rollback $input: got '$got', wanted '$want')"; fail=1; }
	done <<'CASES'
ab 1 2
ac 3 4
ad 5 6
ax error
CASES
fi
# each way an emit can be taken back is refused, naming the rule
refused() {   # refused FILE RULE TEXT
	"$CLI" tests/emit/$1.hbnf --backend=c 2>&1 > /dev/null | grep -q "rule \`$2\`: .*$3" \
		|| { echo "emit: FAIL ($1: not refused with \"$3\")"; fail=1; }
}
refused overlap-choice top 'can both begin with'
refused overlap-option top 'repeated or optional part'
refused prefix-lits-bad top 'can both begin with'
refused rollback-none top 'can both begin with'
# a repetition that can begin like what follows it is refused by the reader already, emit or none
"$CLI" tests/emit/overlap-repeat.hbnf --backend=c 2>&1 > /dev/null | grep -q 'matched greedily' \
	|| { echo "emit: FAIL (overlap-repeat: not refused)"; fail=1; }
# the reader allows nothing but literals and tokens in a lookahead, so an emit cannot get there
"$CLI" tests/emit/lookahead.hbnf --backend=c 2>&1 > /dev/null | grep -q 'looks at a literal' \
	|| { echo "emit: FAIL (lookahead: an %emit in a lookahead is not refused)"; fail=1; }
refused overlap-called top 'can both begin with'
# the Ada backend generates the %emit of a file that says `language Ada` (the code is Ada: `$$` is the function's result, an element
# is a local variable, `rollback { Name : Type }` names the state a given-up alternative puts back), and gives the same answers
if command -v gnatmake > /dev/null 2>&1; then
	ada_case() {   # NAME DRIVER: the grammar tests/emit/NAME-ada.hbnf and the driver tests/emit/ada/DRIVER.adb, built together
		d=$W/ada-$1; rm -rf "$d"; mkdir -p "$d"; cp tests/emit/ada/*.ad? "$d/"
		"$CLI" tests/emit/$1-ada.hbnf --backend=ada --package=Er > "$d/all.ada" 2> "$d/err" \
			|| { echo "emit: FAIL (ada $1: $(head -c 200 "$d/err"))"; fail=1; return 1; }
		(cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 -gnatws "$2.adb" -o "$2" > cc.txt 2>&1) \
			|| { echo "emit: FAIL (ada $1 does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; return 1; }
		return 0
	}
	ada_run() {   # NAME DRIVER INPUT WANT
		got=$("$W/ada-$1/$2" "$3" 2>&1 | head -1)
		[ "$got" = "$4" ] || { echo "emit: FAIL (ada $1 $3: got '$got', wanted '$4')"; fail=1; }
	}
	if ada_case run run_check; then
		while IFS== read -r input want; do ada_run run run_check "$input" "$want"; done <<'CASES'
[]=0
[t]=1
[f]=0
[t,f,[t,t]]=3
[[[t]],[t,t],f]=3
[t,[]=error 1:6
[t,x=error 1:4
CASES
	fi
	if ada_case runs runs_check; then
		while IFS== read -r input want; do ada_run runs runs_check "$input" "$want"; done <<'CASES'
a(1)=1 3 103
b()=2 2 201
c(0)=1 3 103
c:a=3 3 302
a:b=3 3 302
a=4 2 401
a(=error 1:3
a(2)=error 1:3
d=error 1:1
b(1=error 1:4
CASES
	fi
	if ada_case safe safe_check; then
		ada_run safe safe_check '{}' '{}'; ada_run safe safe_check '{a:t}' '{yp:a}'
		ada_run safe safe_check '{a:t,b:{c:f}}' '{yp:a{np:c}p:b}'; ada_run safe safe_check '{a:x}' 'error'
	fi
	if ada_case unrelated trace_check; then ada_run unrelated trace_check xz done; ada_run unrelated trace_check xyz error; fi
	if ada_case emit-last trace_check; then ada_run emit-last trace_check a one; ada_run emit-last trace_check ab two; fi
	if ada_case prefix-lits trace_check; then
		ada_run prefix-lits trace_check '[ab]' table; ada_run prefix-lits trace_check '[[ab]]' array_table; ada_run prefix-lits trace_check '[ab]]' error
	fi
fi
[ $fail = 0 ] && echo "emit: OK (types read; %emit analysed and generated in C and in Ada, each retry refused)"
exit $fail
