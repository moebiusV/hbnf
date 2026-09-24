#!/bin/sh
# unwind's binding against parse.y: run BOTH parsers on the same unwind.conf
# files and compare what each does with them.
#
#   unwind_yy   = bison's parser from sbin/unwind/parse.y
#   unwind_hbnf = hbnf's (grammars/bind/unwind.hbnf, --conf)
#
# Both get the same main (unwind-ident/harness.c: parse_config and a dump
# of every field of the struct uw_conf it returns), unwind's log.c, and the
# pieces of unwind.c and resolver.c the parse needs.  For every
# unwind-ident/cases/*.conf, run in that directory (includes are relative
# to it), both must agree on the exit status, the dump, and the messages
# on stderr, byte for byte, except for cases named syntax-*.conf: there
# parse.y says "syntax error" and hbnf gives a caret message, so only the
# file:line of each error is compared.  Cases named known-*.conf differ in
# their messages, and only the exit status is compared:
#   known-macro-undefined  parse.y follows "macro 'nope' not defined" with
#                          a "syntax error" on the same line; hbnf does not.
#   known-unclosed         a block open at the end of the file: parse.y
#                          reports the line after the last, hbnf the last.
#
# Requires what byteident.sh does: gcc, the extracted OpenBSD tree
# (OBSD=, see README.md), bison, and hbnf_cli.  KEEP=1 keeps the scratch
# directory.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"                        # sources/hbnf
obsd="${OBSD:-$(cd "$here/../../../.." && pwd)/.work/obsd79}"
root="$obsd/extracted"
unwind="$root/sbin/unwind"
t="$here/unwind-ident"

[ -d "$root/sys" ] || { echo "unwind-ident: no OpenBSD tree at $root (set OBSD=)" >&2; exit 1; }
[ -e "$root/sys/machine" ] || ln -s arch/amd64/include "$root/sys/machine"

gccinc="$(gcc -print-file-name=include)"
# unwind's directory first: its "log.h" is not libevent's.
inc="-nostdinc -isystem $gccinc -I $unwind -I $here/bsdinc \
	-I $root/include -I $root/lib/libc/include \
	-I $root/sys -I $root/sys/arch/amd64/include \
	-I $root/lib/libevent -I $root/lib/libutil"

scratch="$(mktemp -d "$obsd/unwind-ident.XXXXXX")"
if [ "${KEEP:-0}" = 1 ]; then echo "scratch: $scratch"
else trap 'rm -rf "$scratch"' EXIT; fi

echo "== bison: parse.y -> parser =="
(cd "$unwind" && bison -d -o "$scratch/parse_y.c" parse.y)

echo "== hbnf: grammars/bind/unwind.hbnf -> conf.c =="
cli="${HBNF_CLI:-$repo/hbnf_cli}"
(cd "$repo" && "$cli" grammars/bind/unwind.hbnf --backend=c --conf) \
	> "$scratch/conf-out.txt"
awk '/^===== conf\.h =====$/{f=1;next} /^===== conf\.c =====$/{f=2;next} \
     f==1{print > "'"$scratch"'/conf.h"} f==2{print > "'"$scratch"'/conf.c"}' \
	"$scratch/conf-out.txt"

echo "== the generated parser, built as unwind's sources are =="
sh "$here/strict-cc.sh" "$root" "$unwind" "$scratch/conf.c"

echo "== compiling =="
gcc -w -std=gnu11 -c $inc "$unwind/log.c" -o "$scratch/log.o"
gcc -w -std=gnu11 -c $inc "$t/harness.c" -o "$scratch/harness.o"
gcc -w -std=gnu11 -c $inc "$t/shims.c" -o "$scratch/shims.o"
gcc -w -std=gnu11 -c $inc "$here/byteident/getaddrinfo_wrap.c" -o "$scratch/gaiwrap.o"
# parse.y calls calloc, strdup, strlen, memset and strlcpy with no
# <stdlib.h> or <string.h>: on OpenBSD another header brings them in, here
# nothing does, and an implicit bsearch() truncated lookup()'s pointer.
gcc -w -std=gnu11 -c $inc -include stdlib.h -include string.h \
	"$scratch/parse_y.c" -o "$scratch/parse_y.o"
gcc -w -std=gnu11 -c $inc -I "$scratch" "$scratch/conf.c" -o "$scratch/conf.o"

echo "== linking =="
wrap="-Wl,--wrap=getaddrinfo -Wl,--wrap=inet_pton"
common="$scratch/log.o $scratch/harness.o $scratch/shims.o $scratch/gaiwrap.o"
gcc -o "$scratch/unwind_yy" "$scratch/parse_y.o" $common $wrap
gcc -o "$scratch/unwind_hbnf" "$scratch/conf.o" $common $wrap

echo "== comparing =="
fail=0; n=0
cd "$t/cases"
for c in *.conf; do
	name=$(basename "$c" .conf); n=$((n + 1))
	set +e
	"$scratch/unwind_yy" "$c" > "$scratch/yy.out" 2> "$scratch/yy.err"; yrc=$?
	"$scratch/unwind_hbnf" "$c" > "$scratch/hb.out" 2> "$scratch/hb.err"; hrc=$?
	set -e
	why=""
	[ "$yrc" = "$hrc" ] || why="exit $yrc vs $hrc"
	[ -n "$why" ] || cmp -s "$scratch/yy.out" "$scratch/hb.out" || why="tree differs"
	case "$name" in
	known-*) ;;
	syntax-*)
		for w in yy hb; do
			grep -o '^[^ ][^:]*:[0-9]*:' "$scratch/$w.err" > "$scratch/$w.lines" || true
		done
		[ -n "$why" ] || cmp -s "$scratch/yy.lines" "$scratch/hb.lines" \
			|| why="error lines differ" ;;
	*) [ -n "$why" ] || cmp -s "$scratch/yy.err" "$scratch/hb.err" \
		|| why="error text differs" ;;
	esac
	if [ -z "$why" ]; then
		printf '  %-28s same (exit %s)\n' "$name" "$yrc"
	else
		printf '  %-28s DIFFER: %s\n' "$name" "$why"; fail=1
		diff -u "$scratch/yy.out" "$scratch/hb.out" | head -20
		diff -u "$scratch/yy.err" "$scratch/hb.err" | head -20
	fi
done
if [ "$fail" = 0 ]; then
	echo "unwind-ident: IDENTICAL ($n cases)"
else
	echo "unwind-ident: DIFFER" >&2
	exit 1
fi
