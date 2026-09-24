#!/bin/sh
# ntpd -n proof: build the real OpenBSD ntpd with hbnf's generated parser in
# place of parse.y, then run `ntpd -n` (configtest) against it.
#
#   parse.y   ->  grammars/bind/ntpd.hbnf  (hbnf_cli --conf emits conf.h/conf.c)
#   the rest of ntpd is compiled as-is from the OpenBSD source tree, against
#   OpenBSD's own headers under -nostdinc (see README.md for the recipe).
#   ntpd-shims.c bridges the OpenBSD libc/syscall names glibc spells
#   differently, and stubs the runtime-only pieces `-n` never reaches.
#
# Requires: host gcc, the extracted OpenBSD tree (see README.md), and
# hbnf_cli: $HBNF_CLI or sources/hbnf/hbnf_cli when built, else docker (the
# ada-toolchain image).
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"                        # sources/hbnf
obsd="${OBSD:-$(cd "$here/../../../.." && pwd)/.work/obsd79}"
root="$obsd/extracted"
ntpd="$root/usr.sbin/ntpd"

[ -d "$root/sys" ] || { echo "ntpd-proof: no OpenBSD tree at $root (set OBSD=)" >&2; exit 1; }
[ -e "$root/sys/machine" ] || ln -s arch/amd64/include "$root/sys/machine"

gccinc="$(gcc -print-file-name=include)"
common_inc="-nostdinc -isystem $gccinc -I $here/bsdinc \
	-I $root/include -I $root/lib/libc/include \
	-I $root/sys -I $root/sys/arch/amd64/include \
	-I $root/lib/libevent -I $root/lib/libutil -I $root/lib/libtls"
inc="$common_inc -I $ntpd"

scratch="$(mktemp -d "$obsd/ntpdproof.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

echo "== generating the parser (hbnf_cli) =="
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

echo "== compiling ntpd + imsg + the generated parser + shims =="
for f in log config constraint util ntp ntp_msg server client sensors \
	ntp_dns control ntpd; do
	gcc -w -std=gnu11 -c $inc "$ntpd/$f.c" -o "$scratch/$f.o"
done
for f in imsg imsg-buffer; do
	gcc -w -std=gnu11 -c $inc -I "$root/lib/libutil" "$root/lib/libutil/$f.c" \
		-o "$scratch/$f.o"
done
gcc -w -std=gnu11 -c $inc "$scratch/conf.c" -o "$scratch/conf.o"
gcc -w -std=gnu11 -c $inc "$here/ntpd-shims.c" -o "$scratch/shims.o"
# glibc fills sockaddrs in its own layout (no sin_len, AF_INET6 = 10); the
# wrappers rewrite them into OpenBSD's, as byteident.sh does, so host() and
# parse.y's address-family checks read them correctly.
gcc -w -std=gnu11 -c $inc "$here/byteident/getaddrinfo_wrap.c" \
	-o "$scratch/gaiwrap.o"

echo "== what the rest of ntpd needs from its parser =="
# Link everything but the parser: what is left undefined is what parse.y
# gives the rest of the daemon, so the generated parser must define it.
need=$(gcc -o /dev/null $(ls "$scratch"/*.o | grep -v '/conf\.o$') -lm \
	-Wl,--wrap=getaddrinfo -Wl,--wrap=inet_pton 2>&1 \
	| sed -n "s/.*undefined reference to \`\([^']*\)'.*/\1/p" | sort -u)
[ -n "$need" ] || { echo "ntpd-proof: nothing left undefined without the parser?" >&2; exit 1; }
miss=0
for sym in $need; do
	if nm -g --defined-only "$scratch/conf.o" | grep -q " $sym\$"; then
		echo "  $sym: defined by the generated parser"
	else
		echo "  $sym: MISSING from the generated parser"; miss=1
	fi
done
[ "$miss" = 0 ] || exit 1

echo "== linking =="
gcc -o "$scratch/ntpd" "$scratch"/*.o -lm \
	-Wl,--wrap=getaddrinfo -Wl,--wrap=inet_pton

echo "== running ntpd -n (configtest) =="
cat > "$scratch/test.conf" <<'EOF'
listen on 0.0.0.0
query from 192.0.2.1
server 10.0.0.1 weight 5 trusted
sensor uds0 correction 10 stratum 2 weight 4 trusted
constraints from "https://www.google.com/"
EOF
"$scratch/ntpd" -n -f "$scratch/test.conf"

echo "== running ntpd -n on a config parse.y rejects =="
printf 'server 10.0.0.1 weight 11\n' > "$scratch/bad.conf"
if "$scratch/ntpd" -n -f "$scratch/bad.conf"; then
	echo "ntpd-proof: bad.conf was accepted" >&2
	exit 1
fi
echo "rejected, as parse.y does"
