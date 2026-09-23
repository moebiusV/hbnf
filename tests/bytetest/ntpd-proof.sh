#!/bin/sh
# ntpd -n proof: build the real OpenBSD ntpd with hbnf's generated parser in
# place of parse.y, then run `ntpd -n` (configtest) against it.
#
#   parse.y   ->  grammars/ntpd.hbnf  (hbnf_cli --conf emits conf.h/conf.c)
#   the rest of ntpd is compiled as-is from the OpenBSD source tree, against
#   OpenBSD's own headers under -nostdinc (see README.md for the recipe).
#   ntpd-shims.c bridges the OpenBSD libc/syscall names glibc spells
#   differently, and stubs the runtime-only pieces `-n` never reaches.
#
# Requires: host gcc, docker (for hbnf_cli, built in the ada-toolchain image),
# and the extracted OpenBSD tree (see README.md).
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

echo "== generating the parser (hbnf_cli, in the ada-toolchain container) =="
docker run --rm -v "$repo":/work -w /work ada-toolchain:edge-full \
	sh -lc 'gprbuild -q -P hbnf_cli.gpr >/dev/null 2>&1
	        ./hbnf_cli grammars/ntpd.hbnf --backend=c --conf' \
	> "$scratch/conf-out.txt"
awk '/^===== conf\.h =====$/{f=1;next} /^===== conf\.c =====$/{f=2;next} \
     f==1{print > "'"$scratch"'/conf.h"} f==2{print > "'"$scratch"'/conf.c"}' \
	"$scratch/conf-out.txt"

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

echo "== linking =="
gcc -o "$scratch/ntpd" "$scratch"/*.o -lm

echo "== running ntpd -n (configtest) =="
cat > "$scratch/test.conf" <<'EOF'
listen on 0.0.0.0
query from 192.0.2.1
server 10.0.0.1 weight 5 trusted
sensor uds0 correction 10 stratum 2 weight 4 trusted
constraints from "https://www.google.com/"
EOF
"$scratch/ntpd" -n -f "$scratch/test.conf"
