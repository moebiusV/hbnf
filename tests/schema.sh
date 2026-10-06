#!/bin/sh
# The obconf configuration-file grammar (hbnf_schema.hbnf), generated in every
# backend and run over the conformance files in tests/accept and tests/reject:
# each accept file must parse and each reject file must not.  This is the
# grammar the hand-written reader HBNF_Config (retired in 9c) was checked
# against.
#
# The same four-backend harness also runs the repetition grammars at the end:
# a repeated rule that can match nothing must terminate (RFCPLAN decision 9),
# which the interpreter HBNF_Match (retired in 9c) used to be the only test of.
#
# One reject file is left out, and says why: 005-decimal-overflow.conf is `x
# 1e40`, refused because the hand-written reader's fixed-point Decimal cannot
# hold it.  A grammar has no value range, so the generated parser reads `1e40`
# as a word and accepts it; that is the Decimal type, not the notation.
#
# SCHEMA_BACKENDS says which backends are gated (default: all four).
#   HBNF=/path/to/hbnf sh tests/schema.sh      (default ./hbnf)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
BACKENDS="${SCHEMA_BACKENDS:-c ada rust zig}"
want() { case " $BACKENDS " in *" $1 "*) return 0 ;; esac; return 1; }

. tests/suite.sh

ACCEPT=$(ls tests/accept/*.conf)
REJECT=$(ls tests/reject/*.conf | grep -v 005-decimal-overflow)
suite schema hbnf_schema.hbnf

# A repeated rule that can match nothing: `empty` matches `a` or nothing.  Each
# shape must accept the empty text, `a` and `a a`, refuse `aa` (one bareword,
# not the keyword), and above all END: it used to loop forever on `aa`.  The
# grammars name `word`, so "a" is a keyword (without words it is the byte).
mkdir "$W/rep"
printf '' > "$W/rep/empty.txt"
printf 'a' > "$W/rep/a.txt"
printf 'a a' > "$W/rep/a_a.txt"
printf 'aa' > "$W/rep/aa.txt"
ACCEPT="$W/rep/empty.txt $W/rep/a.txt $W/rep/a_a.txt"
REJECT="$W/rep/aa.txt"
n=0
for body in 'config = *empty' 'config = 1*empty' 'config = *( [ "a" ] )'; do
	n=$((n + 1))
	{ printf 'language C\n%s\n' "$body"; printf 'empty = [ "a" ]\nw = word\n'; } > "$W/rep/g$n.hbnf"
	suite "repeat $n" "$W/rep/g$n.hbnf"
done

exit $rc
