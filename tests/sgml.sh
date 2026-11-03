#!/bin/sh
# SGML (corpus/sgml/sgml.hbnf): the good files of corpus/sgml/tests/good must be accepted and the bad ones
# refused, in every backend.  A .sgml file is a whole document (the grammar's first rule, `document`), a .dtd file
# a file of declarations (--root=dtd).  Then, in the C parser, each bad file must be refused at the line
# corpus/sgml/tests/bad/REASONS.tsv gives (name, line, reason), so that a file is not refused by accident, for
# some other fault than the one it states.
#   HBNF=/path/to/hbnf sh tests/sgml.sh      (default ./hbnf)
#   SGML_BACKENDS="c rust" sh tests/sgml.sh  just those backends
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${SGML_BACKENDS:-c ada rust zig}"
. tests/suite.sh
G=corpus/sgml/sgml.hbnf
ACCEPT=$(ls corpus/sgml/tests/good/*.sgml)
REJECT=$(ls corpus/sgml/tests/bad/*.sgml)
suite "sgml documents" $G
ACCEPT=$(ls corpus/sgml/tests/good/*.dtd)
REJECT=$(ls corpus/sgml/tests/bad/*.dtd)
suite "sgml declarations" $G dtd

# where each bad file is refused
if want c && command -v cc > /dev/null 2>&1; then
	for root in document dtd; do
		"$CLI" $G --root=$root --backend=c > "$W/$root.c" 2> "$W/$root.err" || { echo "sgml: C FAIL (does not generate $root)"; rc=1; continue; }
		r=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$root.c")
		cat "$W/$root.c" corpus/c/check.c > "$W/$root.m.c"
		cc -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$r" "$W/$root.m.c" -o "$W/$root" || { echo "sgml: C FAIL (cc $root)"; rc=1; continue; }
	done
	while IFS="$(printf '\t')" read -r name line reason; do
		case $name in *.dtd) b=dtd ;; *) b=document ;; esac
		[ -x "$W/$b" ] || continue
		got=$("$W/$b" "corpus/sgml/tests/bad/$name" | sed -n 's/^bad [^:]*: \([0-9]*\):.*/\1/p')
		[ "$got" = "$line" ] || { echo "sgml: C FAIL ($name: refused at line ${got:-none}, REASONS.tsv says $line: $reason)"; rc=1; }
	done < corpus/sgml/tests/bad/REASONS.tsv
fi
[ $rc = 0 ] && echo "sgml: OK" || { echo "sgml: FAIL"; exit 1; }
