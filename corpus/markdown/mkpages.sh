#!/bin/sh
# mkpages.sh - make a GitHub Pages site from the Markdown files in a tree, with Jekyll off.
#
#   HBNF_DIR=/path/to/hbnf sh mkpages.sh ROOT [OUT]
#
# Each ROOT/dir/NAME.md becomes OUT/dir/NAME.html, and each README.md becomes index.html
# (README.html when the directory has an index.md or a hand-written index.html).  OUT defaults
# to ROOT, which is what a repository wants; give another directory to try it without touching
# the tree.  A .nojekyll file is put in OUT so Pages serves the files as they are: nothing
# reads {{ or {% in the text, and nothing is built at deploy time.
#
# A generated page starts with a comment that names its source.  A page without that comment
# is somebody's own and is never overwritten; a generated page whose source is gone is removed.
# In a git repository only tracked files are published.  Links to X.md are written as X.html.  A file ROOT/.mkpagesignore lists path prefixes (one per
# line, relative to ROOT) whose Markdown is left alone, for example test fixtures.  Directories .git, .github, .claude, node_modules and
# _site are skipped.
#
# The pages are made by corpus/markdown/markdown.hbnf and html.c, so what that grammar does
# not cover (README.md of this directory lists it) is read as text.
set -eu
[ $# -ge 1 ] || { echo "usage: HBNF_DIR=/path/to/hbnf sh mkpages.sh ROOT [OUT]" >&2; exit 2; }
ROOT=$(cd "$1" && pwd)
OUT=${2:-$ROOT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
HBNF_DIR=${HBNF_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}
export HBNF_TEMPLATES="$HBNF_DIR/templates"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

"$HBNF_DIR/hbnf" "$HBNF_DIR/corpus/markdown/markdown.hbnf" --backend=c --layout=tape > "$W/md.c"
cat "$W/md.c" "$HBNF_DIR/corpus/markdown/html.c" > "$W/h.c"
${CC:-cc} -O1 -std=gnu11 -w -D_GNU_SOURCE -I"$HBNF_DIR/runtime" -DOUT_T=document_t -o "$W/md2html" "$W/h.c"

made=0 same=0 kept=0 bad=0
if git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1 && [ "$(git -C "$ROOT" rev-parse --show-toplevel)" = "$ROOT" ]; then
	# in a repository only the files git tracks (or has staged) are published, never a draft lying beside them
	git -C "$ROOT" ls-files -- '*.md' | grep -vE '(^|/)(\.git|\.github|\.claude|node_modules|_site)/' \
		| while IFS= read -r f; do [ -f "$ROOT/$f" ] && printf '%s\n' "$ROOT/$f"; done | sort > "$W/list"
else
	find "$ROOT" \( -name .git -o -name .github -o -name .claude -o -name node_modules -o -name _site \) -prune \
		-o -type f -name '*.md' -print | sort > "$W/list"
fi

while IFS= read -r md; do
	rel=${md#"$ROOT"/}
	skip=0
	if [ -f "$ROOT/.mkpagesignore" ]; then
		while IFS= read -r pre; do
			[ -n "$pre" ] || continue
			case "$rel" in "$pre"*) skip=1 ;; esac
		done < "$ROOT/.mkpagesignore"
	fi
	[ "$skip" = 0 ] || continue
	dir=$(dirname "$rel"); name=$(basename "$rel" .md)
	if [ "$name" = README ] && [ ! -e "$ROOT/$dir/index.md" ] && \
	   { [ ! -e "$ROOT/$dir/index.html" ] || grep -q '^<!-- generated from ' "$ROOT/$dir/index.html"; }; then
		name=index
	fi
	html="$OUT/$dir/$name.html"
	if [ -e "$html" ] && ! head -3 "$html" | grep -q '^<!-- generated from '; then
		echo "mkpages: $dir/$name.html is not generated, left alone" >&2; kept=$((kept + 1)); continue
	fi
	mkdir -p "$OUT/$dir"
	if ! "$W/md2html" "$md" - "$rel" > "$W/page.html" 2> "$W/err"; then
		echo "mkpages: $rel: $(head -c 200 "$W/err")" >&2; bad=$((bad + 1)); continue
	fi
	if [ -e "$html" ] && cmp -s "$W/page.html" "$html"; then same=$((same + 1)); continue; fi
	cp "$W/page.html" "$html"; made=$((made + 1))
done < "$W/list"

# a generated page whose source is gone
removed=0
find "$OUT" \( -name .git -o -name .github -o -name .claude -o -name node_modules -o -name _site \) -prune \
	-o -type f -name '*.html' -print | while IFS= read -r h; do
	src=$(head -3 "$h" | sed -n 's/^<!-- generated from \(.*\) by md2html;.*/\1/p')
	[ -n "$src" ] && [ ! -e "$ROOT/$src" ] && { rm -f "$h"; echo "mkpages: removed $h (its source is gone)" >&2; }
done || true

: > "$OUT/.nojekyll"
echo "mkpages: $made written, $same unchanged, $kept left alone, $bad failed"
[ "$bad" -eq 0 ]
