#!/bin/sh
# Patterns as arguments of a parameterised rule, and the literal join `+` (ABNF.md): the rules of
# tests/pattern/pattern.hbnf are made when the grammar is read, so every backend reads them as
# ordinary rules.  Each line of a cases file is a verdict (ok or bad) and an input.  A grammar in
# tests/pattern/bad_NAME.hbnf is refused with a message containing the first line of bad_NAME.want;
# one in ok_NAME.hbnf must generate, and contain each line of ok_NAME.has (and none that starts with !).
#   HBNF=/path/to/hbnf sh tests/pattern.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
n=0; fail=0

# parsers GRAMMAR CASES BACKENDS: the parser of GRAMMAR in each of the backends listed (those
# installed), run on the inputs of CASES.
parsers() {
	g=$1; cases=$2; list=$3; t=$(basename "$g" .hbnf)
	rm -rf "$W/cases"; mkdir -p "$W/cases"; i=0
	while IFS="$(printf '\t')" read -r want input; do
		i=$((i + 1)); printf '%s' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
	done < "$cases"
	nc=$i
	for b in $list; do
		d=$W/$t-$b; mkdir -p "$d"
		case $b in
		c)    command -v cc > /dev/null 2>&1 || continue ;;
		rust) command -v rustc > /dev/null 2>&1 || continue ;;
		zig)  command -v zig > /dev/null 2>&1 || continue ;;
		ada)  command -v gnatmake > /dev/null 2>&1 || continue ;;
		esac
		if [ $b = ada ]; then
			"$CLI" "$g" --backend=ada --package=Lk > "$d/all.ada" 2> "$d/err"
		else
			"$CLI" "$g" --backend=$b > "$d/p.$b" 2> "$d/err"
		fi || { echo "pattern: FAIL ($t does not generate for $b: $(head -c 300 "$d/err"))"; fail=1; continue; }
		case $b in
		c)
			root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$d/p.c")
			cat "$d/p.c" corpus/c/check.c > "$d/m.c"
			cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$d/m.c" -o "$d/m" 2> "$d/cc.txt" \
				|| { echo "pattern: FAIL ($t, C does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		rust)
			sed "s/MODULE/p/g" corpus/c/check.rs > "$d/m.rs"; mv "$d/p.rust" "$d/p.rs"
			(cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1) \
				|| { echo "pattern: FAIL ($t, Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		zig)
			: > "$d/files.txt"; k=1
			while [ $k -le $nc ]; do
				cp "$W/cases/c$k.txt" "$d/f$k.dat"
				printf '    .{ .name = "c%d.txt", .data = @embedFile("f%d.dat") },\n' $k $k >> "$d/files.txt"
				k=$((k + 1))
			done
			mv "$d/p.zig" "$d/l.zig"
			sed "s/MODULE/l.zig/g" corpus/c/check.zig \
				| awk -v f="$d/files.txt" '$0 == "FILES" { while ((getline l < f) > 0) print l; next } { print }' > "$d/m.zig"
			(cd "$d" && zig build-exe m.zig -O ReleaseFast -femit-bin=m > cc.txt 2>&1) \
				|| { echo "pattern: FAIL ($t, Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" > "$d/out" 2>&1 ;;
		ada)
			root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
			sed "s/MODULE/Lk/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
			(cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1) \
				|| { echo "pattern: FAIL ($t, Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		esac
		k=1
		while [ $k -le $nc ]; do
			want=$(cat "$W/cases/c$k.want")
			got=$(grep -F "c$k.txt" "$d/out" | head -1 | cut -d' ' -f1)
			[ -n "$got" ] || got=none
			[ "$got" = "$want" ] || { echo "pattern: FAIL ($t, $b: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
			k=$((k + 1))
		done
		n=$((n + 1))
	done
}

# The rules of the design, with words that are Ada names.
parsers tests/pattern/pattern.hbnf tests/pattern/cases.txt "c rust zig ada"
# An underscore joined on (`"__" + K`): the Ada backend names the value of a literal from its text, and
# `Gnu___const` is no Ada name, written whole (`"__const"`) or joined, so this one has no Ada leg.
parsers tests/pattern/underscore.hbnf tests/pattern/underscore-cases.txt "c rust zig"

# A file whose literals ignore case.
parsers tests/pattern/nocase.hbnf tests/pattern/nocase-cases.txt "c rust zig ada"

# A pattern of alternatives inside a lookahead (C first; the other backends follow).
parsers tests/pattern/lookalt.hbnf tests/pattern/lookalt-cases.txt "c"

# Tree-sitter is generated only.
for g in pattern underscore nocase; do
	"$CLI" tests/pattern/$g.hbnf --backend=tree-sitter > "$W/$g.js" 2> "$W/err" \
		|| { echo "pattern: FAIL ($g does not generate for Tree-sitter: $(head -c 300 "$W/err"))"; fail=1; }
done
for f in tests/pattern/ok_*.hbnf; do
	k=$(basename "$f" .hbnf)
	"$CLI" "$f" --backend=c > "$W/$k.c" 2> "$W/$k.err" \
		|| { echo "pattern: FAIL ($k: $(head -c 300 "$W/$k.err"))"; fail=1; continue; }
	while IFS= read -r want; do
		case $want in
		'!'*) ! grep -qF -- "${want#!}" "$W/$k.c" || { echo "pattern: FAIL ($k: \`${want#!}\` is in the parser)"; fail=1; } ;;
		*)    grep -qF -- "$want" "$W/$k.c" || { echo "pattern: FAIL ($k: \`$want\` is not in the parser)"; fail=1; } ;;
		esac
	done < "tests/pattern/$k.has"
done
for f in tests/pattern/bad_*.hbnf; do
	k=$(basename "$f" .hbnf)
	want=$(head -1 "tests/pattern/$k.want")
	if "$CLI" "$f" --backend=c > /dev/null 2> "$W/$k.err"; then
		echo "pattern: FAIL ($k: accepted)"; fail=1
	elif ! grep -qF -- "$want" "$W/$k.err"; then
		echo "pattern: FAIL ($k: message was: $(head -c 400 "$W/$k.err"))"; fail=1
	fi
done
[ $fail = 0 ] || exit 1
echo "pattern: OK (patterns as arguments and the literal join in $n parser(s), Tree-sitter generated, the refusals)"
