#!/bin/sh
# inner.sh -- inside the Haskell container, pinned to one cpu: each parser is first asked about the
# good and bad files of the format's corpus (it must accept the one and refuse the other, or the row
# says where it does not), then timed, one cold parse per process, the best of RUNS.  Prints one TSV
# row each: FORMAT LABEL MS RSS_KIB STATUS NOTE.
set -u
RUNS=${RUNS:-5}
cd /o

best() {   # best FORMAT LABEL DOC NOTE CMD...: least parse time of RUNS runs
	fmt=$1; label=$2; doc=$3; note=$4; shift 4
	i=0; bm=""; br=""; st=ok
	while [ $i -lt "$RUNS" ]; do
		out=$("$@" "$doc" 2> /o/err.txt | tail -1)
		case $out in ok*) ;; *) st="refused: $(head -c 80 /o/err.txt | tr '\n\t' '  ')"; break ;; esac
		ms=$(echo "$out" | awk '{print $3}'); rss=$(echo "$out" | awk '{print $4}')
		if [ -z "$bm" ] || awk -v a="$ms" -v b="$bm" 'BEGIN{exit !(a<b)}'; then bm=$ms; br=$rss; fi
		i=$((i + 1))
	done
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$fmt" "$label" "${bm:-0}" "${br:-0}" "$st" "$note"
}

agree() {   # agree PROG CORPUS: how many files of CORPUS/good and CORPUS/bad it answers as the corpus says
	prog=$1; dir=$2; n=0; wrong=""
	for f in "$dir"/good/*; do
		[ -f "$f" ] || continue; n=$((n + 1))
		"$prog" -c "$f" 2> /dev/null | grep -q ' 1$' || wrong="$wrong $(basename "$f")"
	done
	for f in "$dir"/bad/*; do
		[ -f "$f" ] || continue; n=$((n + 1))
		"$prog" -c "$f" 2> /dev/null | grep -q ' 0$' || wrong="$wrong $(basename "$f")"
	done
	if [ -z "$wrong" ]; then echo "agrees with the corpus ($n files)"
	else echo "differs from the corpus on:$wrong"; fi
}

W=/w/corpus
row() {   # row FORMAT LABEL PROG CORPUS BUILDS
	n=$(agree "/o/bin/$3" "$W/$4")
	best "$1" "$2" "/o/doc.$1" "$n; $5" "/o/bin/$3"
}
row toml "toml-parser (Alex, Happy), as Debian ships it" toml-parser toml/tests "a list of expressions, text as String"
row toml "toml-parser (Alex, Happy), generators in optimising modes" toml-parser-tuned toml/tests "a list of expressions, text as String"
row json "Alex and Happy, as the tutorials write it" json-plain json/tests "a tree, text as slices of the input"
row json "Alex and Happy, tuned" json-tuned json/tests "a tree, text as slices of the input"
row json "aeson" aeson json/tests "a Value, text and numbers converted"
row yaml "HsYAML (events)" hsyaml yaml/tests "the event stream"
row yaml "yaml (libyaml) into a Value" yaml yaml/tests "a Value, text converted"
for n in json toml yaml; do
	best $n "hbnf (C backend), %emit tape" /o/doc.$n "checked by tests/emit.sh against the corpus; a tape, text as offsets" /o/bin/hbnf-$n-tape
done
