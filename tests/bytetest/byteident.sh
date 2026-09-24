#!/bin/sh
# Byte-identity harness: prove hbnf's generated parser is a drop-in for
# parse.y by running BOTH on the same ntpd.conf and comparing the `struct
# ntpd_conf` each builds.
#
#   ntpd_yy   = bison's parser from parse.y  + the daemon's config.c
#   ntpd_hbnf = hbnf's parser (conf.c)        + the same config.c
#
# Each parses the config, then dump_ntpd_conf() serializes the tree
# canonically (scalars by value, strings by content, lists in order — never
# pointers, TAILQ links or padding).  Identical dumps = identical trees.
#
# Requires: host gcc, docker (bison in alpine:edge, hbnf_cli in
# ada-toolchain:edge-full), and the extracted OpenBSD tree (see README.md).
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
trap 'rm -rf "$scratch"' EXIT

echo "== bison: parse.y -> parser =="
docker run --rm -v "$scratch":/out -v "$ntpd":/p -w /p alpine:edge \
	sh -c 'apk add --no-cache bison >/dev/null 2>&1 && bison -d -o /out/parse_y.c parse.y'

echo "== hbnf: grammars/ntpd.hbnf -> conf.c =="
docker run --rm -v "$repo":/work -w /work ada-toolchain:edge-full \
	sh -lc 'gprbuild -q -P hbnf_cli.gpr >/dev/null 2>&1
	        ./hbnf_cli grammars/ntpd.hbnf --backend=c --conf' \
	> "$scratch/conf-out.txt"
awk '/^===== conf\.h =====$/{f=1;next} /^===== conf\.c =====$/{f=2;next} \
     f==1{print > "'"$scratch"'/conf.h"} f==2{print > "'"$scratch"'/conf.c"}' \
	"$scratch/conf-out.txt"

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
wrap="-Wl,--wrap=getaddrinfo"
common="$scratch/config.o $scratch/log.o $scratch/shims.o \
        $scratch/dump.o $scratch/harness.o $scratch/gaiwrap.o"
gcc -o "$scratch/ntpd_yy" "$scratch/parse_y.o" $common -lm $wrap
gcc -o "$scratch/ntpd_hbnf" "$scratch/conf.o" $common -lm $wrap

echo "== comparing =="
cat > "$scratch/test.conf" <<'EOF'
listen on 0.0.0.0
query from 192.0.2.1
servers 10.0.0.1
server 10.0.0.2 weight 8 trusted
constraints from "https://www.google.com/"
constraint from "https://www.example.com/a" 8.8.8.8 8.8.4.4
sensor uds0 correction 5 stratum 3 weight 2 trusted
EOF
"$scratch/ntpd_yy" "$scratch/test.conf" > "$scratch/yy.out" 2>/dev/null
"$scratch/ntpd_hbnf" "$scratch/test.conf" > "$scratch/hbnf.out" 2>/dev/null
if diff -u "$scratch/yy.out" "$scratch/hbnf.out"; then
	echo "byteident: IDENTICAL"
else
	echo "byteident: DIFFER" >&2
	exit 1
fi
