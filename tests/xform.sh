#!/bin/sh
# The transform language is the template language plus integer expressions and the list position (`_i`, `_n`, `_first`,
# `_last`).  The ports in tests/xform/templates say with those what the Ada code says today by filling `sep` and `first`
# (ada_enum, rust_enum); every grammar the tests hold must come out byte for byte the same through the original and
# the ported templates, in each backend that uses them.
#   HBNF=/path/to/hbnf sh tests/xform.sh      (default ./hbnf)
set -u
CLI=${HBNF:-./hbnf}
[ -x "$CLI" ] || { echo "xform: no $CLI"; exit 1; }
HERE=$(pwd)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
mkdir "$T/ported"; cp templates/*.tmpl "$T/ported/"; cp tests/xform/templates/*.tmpl "$T/ported/"
same=0; diff=0; n=0
for g in tests/*/*.hbnf grammars/*.hbnf examples/mini.hbnf; do
	for b in rust ada; do
		"$CLI" "$g" --backend=$b --templates="$HERE/templates" > "$T/o.out" 2> "$T/o.err"; r1=$?
		"$CLI" "$g" --backend=$b --templates="$T/ported" > "$T/p.out" 2> "$T/p.err"; r2=$?
		n=$((n+1))
		if [ $r1 = $r2 ] && cmp -s "$T/o.out" "$T/p.out"; then same=$((same+1)); else diff=$((diff+1)); echo "DIFF $g --backend=$b"; fi
	done
done
# and the two ports really were used: an enum is in the output
"$CLI" tests/enumval/proto.hbnf --backend=ada --templates="$T/ported" | grep -q "type .* is (" && echo "PASS the ported ada_enum renders" || { echo "FAIL the ported ada_enum does not render"; diff=$((diff+1)); }
[ $diff = 0 ] && echo "xform: OK ($n runs identical through the original and the ported templates)" || { echo "xform: $diff differ"; exit 1; }
