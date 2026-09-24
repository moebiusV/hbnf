#!/bin/sh
# Byte-identity harness: prove hbnf's generated parser is a drop-in for
# parse.y by running BOTH on the same ntpd.conf files and comparing what each
# does with them.
#
#   ntpd_yy   = bison's parser from parse.y  + the daemon's config.c
#   ntpd_hbnf = hbnf's parser (conf.c)        + the same config.c
#
# For every byteident/cases/*.conf, both must agree on:
#   - the exit status (accept or reject);
#   - the tree: dump_ntpd_conf() serializes the `struct ntpd_conf` canonically
#     (scalars by value, strings by content, lists in order -- never
#     pointers, TAILQ links or padding);
#   - the error messages, except for cases named syntax-*.conf, where parse.y
#     says "syntax error" and hbnf gives a caret message by design; for those
#     the file:line of every error must match (both read every statement and
#     report each error, not just the first).
#
# Requires: host gcc, the extracted OpenBSD tree (see README.md), bison, and
# hbnf_cli.  Local ones are used when present (bison on PATH; $HBNF_CLI or
# sources/hbnf/hbnf_cli); otherwise docker (bison in alpine:edge, hbnf_cli in
# ada-toolchain:edge-full).  KEEP=1 keeps the scratch directory.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"                        # sources/hbnf
obsd="${OBSD:-$(cd "$here/../../../.." && pwd)/.work/obsd79}"
root="$obsd/extracted"
ntpd="$root/usr.sbin/ntpd"

[ -d "$root/sys" ] || { echo "byteident: no OpenBSD tree at $root (set OBSD=)" >&2; exit 1; }
[ -e "$root/sys/machine" ] || ln -s arch/amd64/include "$root/sys/machine"

gccinc="$(gcc -print-file-name=include)"
common_inc="-nostdinc -isystem $gccinc -I $here/bsdinc \
	-I $root/include -I $root/lib/libc/include \
	-I $root/sys -I $root/sys/arch/amd64/include \
	-I $root/lib/libevent -I $root/lib/libutil -I $root/lib/libtls"
inc="$common_inc -I $ntpd"

scratch="$(mktemp -d "$obsd/byteident.XXXXXX")"
if [ "${KEEP:-0}" = 1 ]; then echo "scratch: $scratch"
else trap 'rm -rf "$scratch"' EXIT; fi

echo "== bison: parse.y -> parser =="
if command -v bison >/dev/null 2>&1; then
	(cd "$ntpd" && bison -d -o "$scratch/parse_y.c" parse.y)
else
	docker run --rm -v "$scratch":/out -v "$ntpd":/p -w /p alpine:edge \
		sh -c 'apk add --no-cache bison >/dev/null 2>&1 && bison -d -o /out/parse_y.c parse.y'
fi

echo "== hbnf: grammars/bind/ntpd.hbnf -> conf.c =="
cli="${HBNF_CLI:-$repo/hbnf_cli}"
if [ -x "$cli" ]; then
	(cd "$repo" && "$cli" grammars/bind/ntpd.hbnf --backend=c --conf) \
		> "$scratch/conf-out.txt"
else
	docker run --rm -v "$repo":/work -w /work ada-toolchain:edge-full \
		sh -lc 'gprbuild -q -P hbnf_cli.gpr >/dev/null 2>&1
		        ./hbnf_cli grammars/bind/ntpd.hbnf --backend=c --conf' \
		> "$scratch/conf-out.txt"
fi
awk '/^===== conf\.h =====$/{f=1;next} /^===== conf\.c =====$/{f=2;next} \
     f==1{print > "'"$scratch"'/conf.h"} f==2{print > "'"$scratch"'/conf.c"}' \
	"$scratch/conf-out.txt"

echo "== the generated parser, built as ntpd's sources are =="
sh "$here/strict-cc.sh" "$root" "$ntpd" "$scratch/conf.c"

echo "== compiling (shared: config.c, log.c, shims, dump, harness) =="
for f in config log; do
	gcc -w -std=gnu11 -c $inc "$ntpd/$f.c" -o "$scratch/$f.o"
done
gcc -w -std=gnu11 -c $inc "$here/ntpd-shims.c" -o "$scratch/shims.o"
gcc -w -std=gnu11 -c $inc "$here/byteident/dump_ntpd_conf.c" -o "$scratch/dump.o"
gcc -w -std=gnu11 -c $inc "$here/byteident/harness.c" -o "$scratch/harness.o"
gcc -w -std=gnu11 -c $inc "$here/byteident/getaddrinfo_wrap.c" -o "$scratch/gaiwrap.o"
gcc -w -std=gnu11 -c $inc "$scratch/parse_y.c" -o "$scratch/parse_y.o"
gcc -w -std=gnu11 -c $inc "$scratch/conf.c" -o "$scratch/conf.o"

echo "== linking =="
wrap="-Wl,--wrap=getaddrinfo -Wl,--wrap=inet_pton"
common="$scratch/config.o $scratch/log.o $scratch/shims.o \
        $scratch/dump.o $scratch/harness.o $scratch/gaiwrap.o"
gcc -o "$scratch/ntpd_yy" "$scratch/parse_y.o" $common -lm $wrap
gcc -o "$scratch/ntpd_hbnf" "$scratch/conf.o" $common -lm $wrap

echo "== comparing =="
fail=0; n=0
for c in "$here"/byteident/cases/*.conf; do
	name=$(basename "$c" .conf); n=$((n + 1))
	set +e
	"$scratch/ntpd_yy" "$c" > "$scratch/yy.out" 2> "$scratch/yy.err"; yrc=$?
	"$scratch/ntpd_hbnf" "$c" > "$scratch/hb.out" 2> "$scratch/hb.err"; hrc=$?
	set -e
	why=""
	[ "$yrc" = "$hrc" ] || why="exit $yrc vs $hrc"
	[ -n "$why" ] || cmp -s "$scratch/yy.out" "$scratch/hb.out" || why="tree differs"
	case "$name" in
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
	echo "byteident: IDENTICAL ($n cases)"
else
	echo "byteident: DIFFER" >&2
	exit 1
fi
