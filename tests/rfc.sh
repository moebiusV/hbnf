#!/bin/sh
# The RFC corpus (rfc-corpus/): each snippet is <id>.bnf, the RFC's text as
# published, and <id>.hbnf, the form hbnf compiles (<id>.md says what changed
# and why).  For every <id>.vectors/<RULE>.accept and .reject, <id>.hbnf is
# generated with --root=RULE and every input line must parse (.accept) or not
# (.reject).
#
# A vector is one line, read with printf's %b: `\r`, `\n`, `\t` and `\NNN` are
# the characters, `\\` a backslash, and an empty line is the empty input.
#
# Every rule runs in C.  The rules listed in rfc-corpus/headline.txt (one `<id>
# <RULE>` per line) run in Ada, Rust and Zig as well.
#   HBNF=/path/to/hbnf sh tests/rfc.sh      (default ./hbnf)
#   RFC_ONLY=rfc3986-1 sh tests/rfc.sh      (one snippet)
#   RFC_QUICK=1 sh tests/rfc.sh             (only the headline rules; what e2e.sh runs)
set -u
cd "$(dirname "$0")/.."
export HBNF_TEMPLATES="${HBNF_TEMPLATES:-$(pwd)/templates}"
CLI=${HBNF:-./hbnf}
T=tests/schema
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
ALL="${RFC_BACKENDS:-c ada rust zig}"
BACKENDS=c
want() { case " $BACKENDS " in *" $1 "*) return 0 ;; esac; return 1; }
. tests/suite.sh

# vectors FILE PREFIX: one file per line, named PREFIX<n>.txt; prints the names.
vectors() {
	n=0
	[ -f "$1" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		printf '%b' "$line" > "$2$n.txt"
		printf '%s ' "$2$n.txt"
	done < "$1"
}

for hb in rfc-corpus/${RFC_ONLY:-rfc*}.hbnf; do
	[ -f "$hb" ] || continue
	r=$(basename "$hb" .hbnf)
	vdir=rfc-corpus/$r.vectors
	for af in "$vdir"/*.accept; do
		[ -f "$af" ] || continue
		rule=$(basename "$af" .accept)
		mkdir -p "$W/$r/$rule"
		ACCEPT=$(vectors "$af" "$W/$r/$rule/a")
		REJECT=$(vectors "$vdir/$rule.reject" "$W/$r/$rule/r")
		BACKENDS=c
		if grep -qx "$r $rule" rfc-corpus/headline.txt 2> /dev/null; then
			BACKENDS=$ALL
		elif [ -n "${RFC_QUICK:-}" ]; then
			continue
		fi
		suite "$r $rule" "$hb" "$rule"
	done
done
exit $rc
