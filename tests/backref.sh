#!/bin/sh
# Back-references (`name as tag` ... `$tag`): a closing tag must repeat the text of the
# opening one.  tests/backref/tags.hbnf is the whole of XML's element structure; the
# output of tests/backref/main.c must be tests/backref/expected.txt, and with --writer
# every accepted document must be written back as it was.  Then a here-document's
# terminator, a raw string's delimiter, and the join with a captured text,
# `"END-" + $K`, in the four backends (each line of a cases file is a verdict, ok or
# bad, and an input), the `$` that stays a character in a string, and the refusals:
# tests/backref/bad_NAME.hbnf is refused with a message that contains the first line of
# bad_NAME.want, whole.
#   HBNF=/path/to/hbnf sh tests/backref.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$CLI" tests/backref/tags.hbnf --backend=c --writer > "$W/t.c" 2> "$W/err" \
    || { echo "backref: FAIL (generate: $(head -c 300 "$W/err"))"; exit 1; }
root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/t.c")
cat "$W/t.c" tests/backref/main.c > "$W/m.c"
cc -std=gnu11 -D_GNU_SOURCE "-DROOT=$root" -Wall -Wno-unused-function -Werror -o "$W/t" "$W/m.c" 2> "$W/cc" \
    || { echo "backref: FAIL (compile)"; head -8 "$W/cc"; exit 1; }
"$W/t" > "$W/got.txt"
[ -z "${BACKREF_UPDATE:-}" ] || cp "$W/got.txt" tests/backref/expected.txt
cmp -s "$W/got.txt" tests/backref/expected.txt || { echo "backref: FAIL"; diff -u tests/backref/expected.txt "$W/got.txt" | head -20; exit 1; }
# the writer gives back what was read
wroot=$(sed -n 's/^static size_t write_\([A-Za-z0-9_]*\) (.*/\1/p' "$W/t.c" | head -1)
cat "$W/t.c" > "$W/w.c"
cat >> "$W/w.c" <<EOC
#include <stdlib.h>
int main(void) {
    static const char *docs[] = { "<a></a>", "<a>t</a>", "<a><b>x</b><b>y</b></a>", "p<a><a>q</a></a>r", NULL };
    int i, bad = 0;
    for (i = 0; docs[i]; i++) {
        $root out; char err[256]; size_t l, c, n; char *s;
        if (!parse_text(docs[i], &out, err, sizeof err, &l, &c)) { printf("no parse %s\n", docs[i]); bad++; continue; }
        n = write_$wroot (&out, NULL, 0);
        s = malloc (n + 1); write_$wroot (&out, s, n + 1);
        if (strcmp (s, docs[i])) { printf("written %s as %s\n", docs[i], s); bad++; }
    }
    return bad != 0;
}
EOC
cc -std=gnu11 -D_GNU_SOURCE -w -o "$W/w" "$W/w.c" 2> "$W/cc2" || { echo "backref: FAIL (compile writer)"; head -5 "$W/cc2"; exit 1; }
"$W/w" || { echo "backref: FAIL (writer)"; exit 1; }

# The same in Rust, Zig and Ada: the lines C printed (tests/backref/main.{rs,zig,adb}).
G=tests/backref/tags.hbnf
if command -v rustc > /dev/null 2>&1; then
	d=$W/rs; mkdir -p "$d"
	"$CLI" $G --backend=rust > "$d/tags.rs" && cp tests/backref/main.rs "$d/m.rs" \
	  && (cd "$d" && rustc --edition 2021 -A warnings -o m m.rs > cc.txt 2>&1) && "$d/m" > "$d/out" 2>&1 \
	  && cmp -s "$d/out" tests/backref/expected.txt || { echo "backref: FAIL (rust)"; head -5 "$d/cc.txt" 2>/dev/null; diff "$d/out" tests/backref/expected.txt | head -5; exit 1; }
fi
if command -v zig > /dev/null 2>&1; then
	d=$W/zg; mkdir -p "$d"
	"$CLI" $G --backend=zig > "$d/tags.zig" && cp tests/backref/main.zig "$d/m.zig" \
	  && (cd "$d" && zig build-exe m.zig -femit-bin=m > cc.txt 2>&1) && "$d/m" > "$d/out" 2>&1 \
	  && cmp -s "$d/out" tests/backref/expected.txt || { echo "backref: FAIL (zig)"; head -5 "$d/cc.txt" 2>/dev/null; diff "$d/out" tests/backref/expected.txt | head -5; exit 1; }
fi
if command -v gnatmake > /dev/null 2>&1; then
	d=$W/ad; mkdir -p "$d"
	"$CLI" $G --backend=ada --package=Tags > "$d/all.ada" && cp tests/backref/main.adb "$d/" \
	  && (cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -gnat2022 main.adb -o m > cc.txt 2>&1) \
	  && "$d/m" > "$d/out" 2>&1 && cmp -s "$d/out" tests/backref/expected.txt \
	  || { echo "backref: FAIL (ada)"; grep -v warning "$d/cc.txt" 2>/dev/null | head -5; diff "$d/out" tests/backref/expected.txt | head -5; exit 1; }
fi

# --- the other back-references, the join, the refusals
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
		fi || { echo "backref: FAIL ($t does not generate for $b: $(head -c 300 "$d/err"))"; fail=1; continue; }
		case $b in
		c)
			root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$d/p.c")
			cat "$d/p.c" corpus/c/check.c > "$d/m.c"
			cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$root" "$d/m.c" -o "$d/m" 2> "$d/cc.txt" \
				|| { echo "backref: FAIL ($t, C does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		rust)
			sed "s/MODULE/p/g" corpus/c/check.rs > "$d/m.rs"; mv "$d/p.rust" "$d/p.rs"
			(cd "$d" && rustc --edition 2021 -A warnings -O -o m m.rs > cc.txt 2>&1) \
				|| { echo "backref: FAIL ($t, Rust does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
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
				|| { echo "backref: FAIL ($t, Zig does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
			"$d/m" > "$d/out" 2>&1 ;;
		ada)
			root=$(grep -o "return [A-Za-z0-9_]*_Type" "$d/all.ada" | head -1 | sed 's/return \(.*\)_Type/\1/')
			sed "s/MODULE/Lk/g; s/ROOT/$root/g" corpus/posix/check.adb > "$d/check.adb"
			(cd "$d" && gnatchop -w all.ada > /dev/null 2>&1 && gnatmake -q -O2 -gnat2022 -gnatws check.adb -o m > cc.txt 2>&1) \
				|| { echo "backref: FAIL ($t, Ada does not compile: $(grep -m2 error "$d/cc.txt" | head -c 300))"; fail=1; continue; }
			"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1 ;;
		esac
		k=1
		while [ $k -le $nc ]; do
			want=$(cat "$W/cases/c$k.want")
			got=$(grep -F "c$k.txt" "$d/out" | head -1 | cut -d' ' -f1)
			[ -n "$got" ] || got=none
			[ "$got" = "$want" ] || { echo "backref: FAIL ($t, $b: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
			k=$((k + 1))
		done
		n=$((n + 1))
	done
}


parsers tests/backref/heredoc.hbnf tests/backref/heredoc-cases.txt "c rust zig ada"
parsers tests/backref/rawstring.hbnf tests/backref/rawstring-cases.txt "c rust zig ada"
# "END-" + $K read as a literal ("END-ADD") when K is kept from one fixed literal ...
parsers tests/backref/join.hbnf tests/backref/join-cases.txt "c rust zig ada"
parsers tests/backref/join-nocase.hbnf tests/backref/join-nocase-cases.txt "c rust zig ada"
# ... and compared at run time when it is not
parsers tests/backref/join-run.hbnf tests/backref/join-run-cases.txt "c rust zig ada"
parsers tests/backref/join-run-nocase.hbnf tests/backref/join-run-nocase-cases.txt "c rust zig ada"
parsers tests/backref/dollar.hbnf tests/backref/dollar-cases.txt "c rust zig ada"

# The static join is a literal: no capture is left in the parser, and the first-byte
# machinery sees "END-ADD" (C: the capture variables are gone).
"$CLI" tests/backref/join.hbnf --backend=c > "$W/join.c" 2> "$W/err" \
	|| { echo "backref: FAIL (join.hbnf: $(head -c 300 "$W/err"))"; fail=1; }
if grep -q 'cp_k_' "$W/join.c"; then echo "backref: FAIL (join.hbnf keeps a capture the literals made useless)"; fail=1; fi
grep -q '"END-ADD"' "$W/join.c" || { echo "backref: FAIL (join.hbnf has no END-ADD literal)"; fail=1; }
"$CLI" tests/backref/join-run.hbnf --backend=c > "$W/jr.c" 2> "$W/err" \
	|| { echo "backref: FAIL (join-run.hbnf: $(head -c 300 "$W/err"))"; fail=1; }
grep -q 'cp_k_' "$W/jr.c" || { echo "backref: FAIL (join-run.hbnf compares at run time and has no capture)"; fail=1; }

# Tree-sitter is generated only (a run-time join is left out, with a note).
for g in tags join join-nocase join-run heredoc rawstring; do
	"$CLI" tests/backref/$g.hbnf --backend=tree-sitter > "$W/$g.js" 2> "$W/err" \
		|| { echo "backref: FAIL ($g does not generate for Tree-sitter: $(head -c 300 "$W/err"))"; fail=1; }
done

for f in tests/backref/bad_*.hbnf; do
	k=$(basename "$f" .hbnf)
	want=$(head -1 "tests/backref/$k.want")
	if "$CLI" "$f" --backend=c > /dev/null 2> "$W/$k.err"; then
		echo "backref: FAIL ($k: accepted)"; fail=1
	elif ! grep -qF -- "$want" "$W/$k.err"; then
		echo "backref: FAIL ($k: message was: $(head -c 400 "$W/$k.err"))"; fail=1
	fi
done
# The old spellings, `%as` and `%same`, are refused, in hbnf's own notation with the new
# spelling in the message and in the dialects with the reason (the files are made here:
# hbnf_modernize.py would rewrite them if they lay in the tree).
refuse() {
	printf '%s\n' "$3" > "$W/old_$1.hbnf"
	if "$CLI" "$W/old_$1.hbnf" --backend=c > /dev/null 2> "$W/old_$1.err"; then
		echo "backref: FAIL (old_$1: accepted)"; fail=1
	elif ! grep -qF -- "$2" "$W/old_$1.err"; then
		echo "backref: FAIL (old_$1: message was: $(head -c 400 "$W/old_$1.err"))"; fail=1
	fi
}
refuse as 'is written `as`' 'prefix none
top  = name %as t ">" "</" t ">"
name = word'
refuse same 'is written `$`' 'prefix none
top  = name as t ">" "</" %same t ">"
name = word'
refuse abnf 'ABNF and the other dialects have no back-reference' 'dialect abnf
top  = name %as t ">" "</" %same t ">"
name = 1*ALPHA'
# and in a dialect other than hbnf's `as` is a name: a rule may be called that
printf 'dialect abnf\ntop = as\nas = "x"\n' > "$W/as_abnf.abnf"
"$CLI" "$W/as_abnf.abnf" --backend=c > /dev/null 2> "$W/err" \
	|| { echo "backref: FAIL (a rule named as in dialect abnf: $(head -c 300 "$W/err"))"; fail=1; }
[ $fail = 0 ] || exit 1
echo "backref: OK (a closing tag repeats the opening one; the writer repeats it too; Rust, Zig and Ada parse it; a here-document, a raw string, the join \"END-\" + \$K in $n parser(s), the refusals)"
