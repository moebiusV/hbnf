#!/bin/sh
# `^.name` in a grammar included `as x` is the rule `name` of the grammar that includes it (`^.^.name`: two
# levels out, `^.sql.statement`: a rule of an island of the parent).  The dot goes in, the caret goes out.
# It is read when the grammar is read, into the scoped name the rest of the generator uses, so the four
# backends need nothing of their own: tests/upscope/host.hbnf (a guest that calls host rules, a host rule
# that reaches the guest again, a lookahead, a pattern argument, a guest of a guest) and two.hbnf (one guest
# file with two parents) are parsed by C, Rust, Zig and Ada; then the refusals, the names kept strict.
#   HBNF=/path/to/hbnf sh tests/upscope.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W" tests/upscope/_m' EXIT
n=0; fail=0
# parsers GRAMMAR CASES BACKENDS: the parser of GRAMMAR in each of the backends listed (those
# installed), run on the inputs of CASES (\n in an input is a line feed).
parsers() {
	g=$1; cases=$2; list=$3; t=$(basename "$g" .hbnf)
	rm -rf "$W/cases"; mkdir -p "$W/cases"; i=0
	while IFS="$(printf '\t')" read -r want input; do
		i=$((i + 1)); printf '%b' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
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
		fi || { echo "upscope: FAIL ($t does not generate for $b: $(head -c 300 "$d/err"))"; fail=1; continue; }
		case $b in
		c)
			root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$d/p.c")
			cat "$d/p.c" corpus/c/check.c > "$d/m.c"
			cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$d/m.c" -o "$d/m" 2> "$d/cc.txt" \
				|| { echo "upscope: FAIL ($t, C does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		rust)
			sed "s/MODULE/p/g" corpus/c/check.rs > "$d/m.rs"; mv "$d/p.rust" "$d/p.rs"
			(cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1) \
				|| { echo "upscope: FAIL ($t, Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
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
				|| { echo "upscope: FAIL ($t, Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" > "$d/out" 2>&1 ;;
		ada)
			root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
			sed "s/MODULE/Lk/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
			(cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1) \
				|| { echo "upscope: FAIL ($t, Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		esac
		k=1
		while [ $k -le $nc ]; do
			want=$(cat "$W/cases/c$k.want")
			got=$(grep -F "c$k.txt" "$d/out" | head -1 | cut -d' ' -f1)
			[ -n "$got" ] || got=none
			[ "$got" = "$want" ] || { echo "upscope: FAIL ($t, $b: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
			k=$((k + 1))
		done
		n=$((n + 1))
	done
}



ALL="c rust zig ada"
parsers tests/upscope/host.hbnf tests/upscope/cases.txt "$ALL"
parsers tests/upscope/two.hbnf tests/upscope/two-cases.txt "$ALL"

# The refusals.  M is a directory beside the guests; a grammar written there is refused with a message.
M=tests/upscope/_m
mkdir -p $M
refuse() {   # NAME WANT: $M/g.hbnf is refused with a message containing WANT
	if "$CLI" "$M/g.hbnf" --backend=c > /dev/null 2> "$W/err"; then
		echo "upscope: FAIL ($1: generated, should be refused)"; fail=1
	elif ! grep -qF -- "$2" "$W/err"; then
		echo "upscope: FAIL ($1: the message lacks \`$2\`: $(head -c 400 "$W/err"))"; fail=1
	fi
}
# the root grammar has nothing out of it
printf 'prefix none\ntop = ^.foo\nfoo = "x"\n' > $M/g.hbnf
refuse "in the root" 'not included `as` anything'
# the parent defines no such rule (the root, and a scope between)
printf 'prefix none\ntop = "a" "b"\nitem = ^.nope\n' > $M/guest.hbnf
printf 'prefix none\ninclude "guest.hbnf" as g\ntop = g.item\n' > $M/g.hbnf
refuse "root defines no such rule" 'the root grammar, which includes `g`, defines no rule `nope`'
printf 'prefix none\nitem = ^.nope\n' > $M/leaf.hbnf
printf 'prefix none\ninclude "leaf.hbnf" as l\nmid = "m"\n' > $M/mid.hbnf
printf 'prefix none\ninclude "mid.hbnf" as m\ntop = m.l.item\n' > $M/g.hbnf
refuse "a scope between defines no such rule" 'the grammar `m`, which includes the grammar `m.l`, defines no rule `nope`'
# too far out
printf 'prefix none\nitem = ^.^.foo\n' > $M/guest.hbnf
printf 'prefix none\ninclude "guest.hbnf" as g\ntop = g.item\nfoo = "x"\n' > $M/g.hbnf
refuse "two levels from one" 'goes 2 level(s) out'
# a scope the parent does not have
printf 'prefix none\nitem = ^.q.foo\n' > $M/guest.hbnf
refuse "a scope the parent lacks" 'no grammar is included `as q`'
# a plain name is still only the guest's own
printf 'prefix none\nitem = foo\n' > $M/guest.hbnf
refuse "a plain name stays missing" 'rule `foo` is not defined in grammar `g`'
# a rule is defined by its plain name
printf 'prefix none\n^.foo = "y"\nitem = "x"\n' > $M/guest.hbnf
refuse "a definition" 'names a rule of the grammar that includes this one'
[ $fail = 0 ] || exit 1
echo "upscope: OK (^.name: a guest calls the host, the host reaches the guest again, a lookahead, a pattern argument, two levels out, one guest with two parents, in $n parser(s); the refusals)"
