#!/bin/sh
# Markdown to Typst (corpus/markdown): the grammar writes a tape, typst.c walks it.  Each corpus/markdown/tests/good/NAME.md
# must be read and come out as NAME.typ, byte for byte.  Any text is Markdown, so there is no bad directory.
#   HBNF=/path/to/hbnf sh tests/markdown.sh      (default ./hbnf; UPDATE=1 writes the .typ files)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
G=corpus/markdown
fail=0; n=0

"$CLI" $G/markdown.hbnf --backend=c --layout=tape > "$W/md.c" 2> "$W/gen.err" \
	|| { echo "markdown: FAIL (generate: $(head -c 300 "$W/gen.err"))"; exit 1; }
[ -s "$W/gen.err" ] && { echo "markdown: FAIL (the generator warned: $(head -c 300 "$W/gen.err"))"; exit 1; }
cat "$W/md.c" $G/typst.c > "$W/m.c"
${CC:-cc} -O1 -std=gnu11 -w -D_GNU_SOURCE -Iruntime -DOUT_T=document_t -o "$W/md2typst" "$W/m.c" 2> "$W/cc.err" \
	|| { echo "markdown: FAIL (compile: $(head -c 300 "$W/cc.err"))"; exit 1; }

for f in $G/tests/good/*.md; do
	n=$((n + 1)); want=${f%.md}.typ
	if ! "$W/md2typst" "$f" > "$W/out.typ" 2> "$W/err.txt"; then
		echo "markdown: FAIL ($f is refused: $(head -c 200 "$W/err.txt"))"; fail=1; continue
	fi
	if [ "${UPDATE:-}" = 1 ]; then cp "$W/out.typ" "$want"; continue; fi
	cmp -s "$W/out.typ" "$want" || { echo "markdown: FAIL ($f does not come out as $want)"; diff "$W/out.typ" "$want" | head -6; fail=1; }
done

# the same documents to HTML (corpus/markdown/html.c walks the same tape): NAME.html, byte for byte
cat "$W/md.c" $G/html.c > "$W/h.c"
${CC:-cc} -O1 -std=gnu11 -w -D_GNU_SOURCE -Iruntime -DOUT_T=document_t -o "$W/md2html" "$W/h.c" 2> "$W/cc.err" \
	|| { echo "markdown: FAIL (compile html: $(head -c 300 "$W/cc.err"))"; exit 1; }
for f in $G/tests/good/*.md; do
	want=${f%.md}.html
	if ! "$W/md2html" "$f" > "$W/out.html" 2> "$W/err.txt"; then
		echo "markdown: FAIL ($f is refused by md2html: $(head -c 200 "$W/err.txt"))"; fail=1; continue
	fi
	if [ "${UPDATE:-}" = 1 ]; then cp "$W/out.html" "$want"; continue; fi
	cmp -s "$W/out.html" "$want" || { echo "markdown: FAIL ($f does not come out as $want)"; diff "$W/out.html" "$want" | head -6; fail=1; }
done

# the same text read twice is the same Typst (no state is kept between parses)
"$W/md2typst" $G/tests/good/report.md > "$W/a.typ"; "$W/md2typst" $G/tests/good/report.md > "$W/b.typ"
cmp -s "$W/a.typ" "$W/b.typ" || { echo "markdown: FAIL (two runs differ)"; fail=1; }

[ $fail = 0 ] && echo "markdown: OK ($n documents come out as their .typ and .html)"
exit $fail
