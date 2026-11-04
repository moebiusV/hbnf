#!/bin/sh
# Captures in a tape: `layout tape` has to read what the tree layout reads, for a back-reference too.
# `x as K` with `$K`, `"lit" + $K`, `$K^` and `$K^R`, a plain `$K` in a group, an option or a lookahead,
# and the case-folding ones: every grammar of tests/backref, tests/upref and tests/upscope with a file of
# cases is generated twice (the tree and --layout=tape), built with the checker of corpus/c/check.c, and run
# on every case: both must give the verdict of the file (ok or bad).  Then the corpus that closes a tag
# by a back-reference (xml, mustache) through the tape with its good and bad folders, and a tape of
# an element that is given up (`<a x="1"` and no more) leaves no word of it.
#   HBNF=/path/to/hbnf sh tests/tapecap.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
n=0; fail=0
command -v cc > /dev/null 2>&1 || { echo "tapecap: skipped (no C compiler)"; exit 0; }

# one GRAMMAR CASES [ROOT]: the verdicts of the tree parser and of the tape parser on each case
one() {
	g=$1; cases=$2; t=$(basename "$g" .hbnf); r=${3:+--root=$3}
	rm -rf "$W/cases"; mkdir -p "$W/cases"; i=0
	while IFS="$(printf '\t')" read -r want input; do
		i=$((i + 1)); printf '%b' "$input" > "$W/cases/c$i.txt"; echo "$want" > "$W/cases/c$i.want"
	done < "$cases"
	nc=$i
	for lay in ast tape; do
		d=$W/$t-$lay; mkdir -p "$d"
		"$CLI" "$g" --backend=c --layout=$lay $r > "$d/p.c" 2> "$d/err" \
			|| { echo "tapecap: FAIL ($t does not generate with --layout=$lay: $(head -c 300 "$d/err"))"; fail=1; continue; }
		root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$d/p.c")
		cat "$d/p.c" corpus/c/check.c > "$d/m.c"
		cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$d/m.c" -o "$d/m" 2> "$d/cc.txt" \
			|| { echo "tapecap: FAIL ($t, $lay: C does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
		"$d/m" "$W"/cases/c*.txt > "$d/out" 2>&1
		k=1
		while [ $k -le $nc ]; do
			want=$(cat "$W/cases/c$k.want")
			got=$(grep -F "c$k.txt" "$d/out" | head -1 | cut -d' ' -f1)
			[ -n "$got" ] || got=none
			[ "$got" = "$want" ] || { echo "tapecap: FAIL ($t, $lay: \`$(cat "$W/cases/c$k.txt")\` should be $want and is $got)"; fail=1; }
			k=$((k + 1))
		done
		n=$((n + 1))
	done
}

one tests/backref/tags.hbnf tests/backref/tags-cases.txt doc
for p in heredoc rawstring join join-nocase join-run join-run-nocase join-group dollar fold-file fold-exact fold-i; do
	one tests/backref/$p.hbnf tests/backref/$p-cases.txt
done
one tests/upref/deep.hbnf tests/upref/deep-cases.txt
one tests/upref/nested.hbnf tests/upref/nested-cases.txt
one tests/upref/two.hbnf tests/upref/two-cases.txt
one tests/upref/two-nocase.hbnf tests/upref/two-nocase-cases.txt
one tests/upref/named.hbnf tests/upref/named-cases.txt
one tests/upref/fence.hbnf tests/upref/fence-cases.txt
one tests/upref/fence-named.hbnf tests/upref/fence-cases.txt
one tests/upref/group.hbnf tests/upref/group-cases.txt
one tests/upref/look.hbnf tests/upref/look-cases.txt
one tests/upref/static.hbnf tests/upref/static-cases.txt
one tests/upref/fold-up.hbnf tests/upref/fold-up-cases.txt
one tests/upscope/host.hbnf tests/upscope/cases.txt
one tests/upscope/two.hbnf tests/upscope/two-cases.txt

# the corpus: a good file is accepted and a bad one refused by the tape as by the tree
folder() {
	g=$1; root=$2; shift 2; t=$(basename "$g" .hbnf)
	for lay in ast tape; do
		d=$W/$t-$lay; mkdir -p "$d"
		"$CLI" "$g" --backend=c --layout=$lay --root=$root > "$d/p.c" 2> "$d/err" \
			|| { echo "tapecap: FAIL ($t does not generate with --layout=$lay: $(head -c 300 "$d/err"))"; fail=1; continue; }
		cat "$d/p.c" corpus/c/check.c > "$d/m.c"
		cc -O1 -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$d/p.c")" \
			"$d/m.c" -o "$d/m" 2> "$d/cc.txt" \
			|| { echo "tapecap: FAIL ($t, $lay: C does not compile: $(head -c 300 "$d/cc.txt"))"; fail=1; continue; }
		for dir in "$@"; do
			want=${dir%%:*}; dir=${dir#*:}
			for f in "$dir"/*; do
				[ -f "$f" ] || continue
				got=$("$d/m" "$f" 2> /dev/null | cut -d' ' -f1)
				[ "$got" = "$want" ] || { echo "tapecap: FAIL ($t, $lay: $f should be $want and is ${got:-none})"; fail=1; }
			done
		done
		n=$((n + 1))
	done
}
# xml keeps the names of a tag's attributes and the declared entities in contexts (a repeated attribute, an entity that
# is not declared ...): the cases of corpus/xml/tests/bad that are about them are in this comparison, and a tape that
# is built next to a context must still hold every word (a rule that puts the contexts back once went to the pass that
# writes none)
folder corpus/xml/xml.hbnf document ok:corpus/xml/tests/good ok:corpus/xml/tests/loose bad:corpus/xml/tests/bad
ls corpus/mustache/tests > /dev/null 2>&1 && folder corpus/mustache/mustache.hbnf "$(sed -n 's/^\([a-z][a-z-]*\) *=.*/\1/p' corpus/mustache/mustache.hbnf | head -1)" ok:corpus/mustache/tests/good bad:corpus/mustache/tests/bad
# (html is not here: CONTEXTS.md section 26 item 63, a lookahead over a rule, is not about captures)

# an abandoned try leaves no word on the tape: abandon.hbnf reads a start tag, gives it up when it does not end in
# "/>" and reads it again; factored.hbnf reads it once.  The tapes of the same documents must be the same words.
cat > "$W/dump.c" <<'EOC'
#include <stdio.h>
int main(int argc, char **argv) {
    char err[256]; size_t l, c, i; OUT_T out; int ok;
    ok = parse_text(argv[1], &out, err, sizeof err, &l, &c);
    printf("%s %lu", ok ? "ok" : "bad", (unsigned long)(ok ? tape_n : 0));
    for (i = 0; ok && i < tape_n; i++) printf(" %llx", (unsigned long long)tape[i]);
    printf("\n");
    return 0;
}
EOC
for g in abandon factored; do
	"$CLI" tests/tapecap/$g.hbnf --backend=c --layout=tape --root=doc > "$W/$g.c" 2> "$W/$g.err" \
		|| { echo "tapecap: FAIL ($g.hbnf does not generate: $(head -c 300 "$W/$g.err"))"; fail=1; continue; }
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$g.c")
	cat "$W/$g.c" "$W/dump.c" > "$W/$g-d.c"
	cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/$g-d.c" -o "$W/$g-d" 2> "$W/$g.cc" \
		|| { echo "tapecap: FAIL ($g.hbnf does not compile: $(head -c 300 "$W/$g.cc"))"; fail=1; continue; }
done
if [ -x "$W/abandon-d" ] && [ -x "$W/factored-d" ]; then
	for doc in '<a/>' '<a x="1"/>' '<a x="1" y="2">t</a>' 'p<a><b x="1"></b><c/></a>q' '<a><a><a/></a></a>' '<a></b>' '<a x="1"'; do
		a=$("$W/abandon-d" "$doc"); b=$("$W/factored-d" "$doc")
		[ "$a" = "$b" ] || { echo "tapecap: FAIL (the tape of \`$doc\` differs: tries '$a', once '$b')"; fail=1; }
		n=$((n + 1))
	done
fi
# the tape of a small document with a context grammar holds the words of the tree: the document, the element, its
# name, the attributes and their values, the text and the empty element inside
cat > "$W/tags.c" <<'EOC'
#include <stdio.h>
int main(int argc, char **argv) {
    char err[256]; size_t l, c, i; OUT_T out; int ok;
    ok = parse_text(argv[1], &out, err, sizeof err, &l, &c);
    for (i = 0; ok && i < tape_n; i++) printf("%s ", tape_tag_names[tape[i] >> 56]);
    printf("\n");
    return 0;
}
EOC
"$CLI" corpus/xml/xml.hbnf --backend=c --layout=tape --root=document > "$W/xt.c" 2> "$W/xt.err" && {
	root=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/xt.c")
	cat "$W/xt.c" "$W/tags.c" > "$W/xt-d.c"
	cc -std=gnu11 -D_GNU_SOURCE -w -I runtime "-DOUT_T=$root" "$W/xt-d.c" -o "$W/xt-d" 2> "$W/xt.cc" || { echo "tapecap: FAIL (xml tags driver: $(head -c 300 "$W/xt.cc"))"; fail=1; }
	got=$("$W/xt-d" '<a x="1">t<b/></a>' 2> /dev/null)
	echo "$got" | grep -q '^document element qname attributes attribute qname .* content chardata element qname' \
		|| { echo "tapecap: FAIL (the tape of an xml document lost words: $got)"; fail=1; }
	n=$((n + 1))
}
[ $fail = 0 ] || exit 1
echo "tapecap: OK (the tape reads what the tree reads, in $n parser(s): back-references, joins, up references, case folding; xml and mustache)"
