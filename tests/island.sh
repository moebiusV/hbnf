#!/bin/sh
# Islands: `include "guest.hbnf" as sql` puts a file's rules in the scope `sql`, and `sql.stmt` reads one of
# them.  tests/island/host.hbnf is a host that skips line ends and is case-sensitive around a guest (a small
# SQL) that does not skip them, ignores case, and has rules of the host's names (`ws`, `name`).  Each line of
# cases.txt is a verdict (ok or bad) and an input (`\n` is a line end); every backend installed must give the
# verdict.  Then the messages: a rule that does not exist in a scope, a scope that does not exist, a rule

#   HBNF=/path/to/hbnf sh tests/island.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W" tests/island/_m' EXIT
n=0; fail=0
mkdir -p "$W/cases"; i=0
while IFS="$(printf '\t')" read -r want input; do
	i=$((i + 1)); printf '%b' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
done < tests/island/cases.txt
nc=$i
verdicts() {   # BACKEND OUTPUT: every case has the verdict written for it
	k=1
	while [ $k -le $nc ]; do
		want=$(cat "$W/cases/c$k.want")
		got=$(grep -F "c$k.txt" "$2" | head -1 | cut -d' ' -f1)
		[ -n "$got" ] || got=none
		[ "$got" = "$want" ] || { echo "island: FAIL ($1: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
		k=$((k + 1))
	done
	n=$((n + 1))
}
H=tests/island/host.hbnf
"$CLI" $H --backend=c > "$W/p.c" 2> "$W/err" || { echo "island: FAIL (does not generate for C: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/p.c")
cat "$W/p.c" corpus/c/check.c > "$W/pm.c"
cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$W/pm.c" -o "$W/pcheck" 2> "$W/cc.err" || { echo "island: FAIL (C: $(head -c 300 "$W/cc.err"))"; exit 1; }
"$W/pcheck" "$W"/cases/c*.txt > "$W/p.out" 2>&1; verdicts c "$W/p.out"
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" $H --backend=rust > "$d/l.rs" 2> "$d/err" || { echo "island: FAIL (does not generate for Rust: $(head -c 300 "$d/err"))"; fail=1; }
	sed "s/MODULE/l/g" corpus/c/check.rs > "$d/m.rs"
	if (cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts rust "$d/out"
	else echo "island: FAIL (Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" $H --backend=zig > "$d/l.zig" 2> "$d/err" || { echo "island: FAIL (does not generate for Zig: $(head -c 300 "$d/err"))"; fail=1; }
	: > "$d/files.txt"; k=1
	while [ $k -le $nc ]; do
		cp "$W/cases/c$k.txt" "$d/f$k.dat"
		printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
		k=$((k + 1))
	done
	sed "s/MODULE/l.zig/g" corpus/c/check.zig | awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
	if (cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1); then
		"$d/m" > "$d/out" 2>&1; verdicts zig "$d/out"
	else echo "island: FAIL (Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; fi
fi
if command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" $H --backend=ada --package=Isl > "$d/all.ada" 2> "$d/err" || { echo "island: FAIL (does not generate for Ada: $(head -c 300 "$d/err"))"; fail=1; }
	root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
	sed "s/MODULE/Isl/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
	if (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1); then
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1; verdicts ada "$d/out"
	else echo "island: FAIL (Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; fi
fi
"$CLI" $H --backend=tree-sitter > "$W/ts.js" 2> "$W/err" || { echo "island: FAIL (does not generate for tree-sitter: $(head -c 300 "$W/err"))"; fail=1; }
[ $fail = 0 ] || exit 1

# The messages.  FILE: the text of a grammar written in $W/m (beside the guest), WANT: what the error says.
refuse() {   # NAME WANT: the grammar in tests/island/_m/g.hbnf is refused with a message containing WANT
	if "$CLI" "tests/island/_m/g.hbnf" --backend=c > /dev/null 2> "$W/err"; then
		echo "island: FAIL ($1: generated, should be refused)"; fail=1
	elif ! grep -qF -- "$2" "$W/err"; then
		echo "island: FAIL ($1: the message lacks \`$2\`: $(head -c 400 "$W/err"))"; fail=1
	fi
}
mkdir -p tests/island/_m; sed 's#\.\./\.\./#../../../#' tests/island/guest.hbnf > tests/island/_m/guest.hbnf
printf 'prefix none\ninclude "guest.hbnf" as sql\ntop = sql.nope\n' > "tests/island/_m/g.hbnf"
refuse "undefined rule in a scope" 'the grammar `sql` defines no rule `nope`; it defines: '
printf 'prefix none\ninclude "guest.hbnf" as sql\ntop = sqll.stmt\n' > "tests/island/_m/g.hbnf"
refuse "unknown scope" 'no grammar is included `as sqll`'
refuse "unknown scope, the known ones" 'the grammars included `as` here are: sql'
printf 'prefix none\ninclude "guest.hbnf" as sql\ntop = sql.stmt\nsql.thing = "x"\n' > "tests/island/_m/g.hbnf"
refuse "a rule defined with a dot" 'a rule'"'"'s name has no dot'
printf 'prefix none\ninclude "guest.hbnf" as\ntop = "x"\n' > "tests/island/_m/g.hbnf"
refuse "as without a name" 'needs the name of the scope'
printf 'prefix none\ninclude "guest.hbnf" as a.b\ntop = "x"\n' > "tests/island/_m/g.hbnf"
refuse "a dotted scope name" "a scope's name has no dot"
# A scope sees only its own file and what that file includes: a rule of the host is not visible in the guest.
printf 'prefix none\nwhitespace none\nstmt = "x" host-only\n' > "tests/island/_m/bad.hbnf"
printf 'prefix none\ninclude "bad.hbnf" as sql\nhost-only = "y"\ntop = sql.stmt\n' > "tests/island/_m/g.hbnf"
refuse "a guest using a host rule" 'rule `host-only` is not defined in grammar `sql`'
refuse "a guest using a host rule, the advice" '`include` the file that defines `host-only`'
refuse "a guest using a host rule, the place" "bad.hbnf:3:"
# One white-space rule per parser: a guest that skips with a rule of its own is refused, not run with the host's.
printf 'prefix none\nwhitespace ws\nws = " "\nstmt = "x" "y"\n' > tests/island/_m/own.hbnf
printf 'prefix none\ninclude "own.hbnf" as sql\nws = " " / "\\n"\ntop = sql.stmt "z"\n' > tests/island/_m/g.hbnf
refuse "a guest with its own ws rule" 'a generated parser has one white-space rule'
# The same file in two scopes, and in the scope and out of it: read for each.
printf 'prefix none\ninclude "guest.hbnf" as one\ninclude "guest.hbnf" as two\ninclude "guest.hbnf"\ntop = one.select two.select select\n' > "tests/island/_m/g.hbnf"
"$CLI" "tests/island/_m/g.hbnf" --backend=c > "$W/m.c" 2> "$W/err" || { echo "island: FAIL (one file in three places: $(head -c 300 "$W/err"))"; fail=1; }
for r in one__select two__select; do
	grep -q "$r" "$W/m.c" || { echo "island: FAIL (one file in three places: no $r)"; fail=1; }
done
[ $fail = 0 ] || exit 1
echo "island: OK (a guest with its own white space and case, the host's names and its own, in $n backend(s); the messages)"
