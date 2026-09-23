#!/bin/sh
# Byte-identity harness against OpenBSD parse.y / config headers.
#
# For each of the nine daemons in daemons.tsv:
#   1. build its parse.y with bison (proves the grammar is brought in and parses);
#   2. compile its real config header against OpenBSD's own headers and dump
#      sizeof(struct conf) — the byte-identity anchor our generated parser
#      must reproduce field-for-field.
#
# The OpenBSD 7.9 source tree (sys.tar.gz + src.tar.gz, extracted) is located
# via $OBSD, defaulting to ../../../../.work/obsd79 relative to this script.
# See README.md for how to fetch and extract it.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
obsd="${OBSD:-$(cd "$here/../../../.." && pwd)/.work/obsd79}"
root="$obsd/extracted"

die() { echo "bytetest: $*" >&2; exit 1; }

[ -d "$root/sys" ] || die "no OpenBSD tree at $root (set OBSD=/path/to/extracted)"

# <machine/...> headers are a symlink created at build time, not shipped in
# the tarball.  Recreate it if missing.
if [ ! -e "$root/sys/machine" ]; then
	ln -s arch/amd64/include "$root/sys/machine"
fi

gccinc="$(gcc -print-file-name=include)"

# OpenBSD headers, self-consistent: kernel + userland + in-tree libs + the
# stdint shim, all under -nostdinc so glibc's conflicting __int64_t (long)
# never appears beside OpenBSD's (long long).  -isystem re-adds only gcc's
# own freestanding headers (stdarg.h, stddef.h, float.h, ...).
common_inc="-nostdinc -isystem $gccinc -I $here/bsdinc \
	-I $root/include -I $root/lib/libc/include \
	-I $root/sys -I $root/sys/arch/amd64/include \
	-I $root/lib/libevent -I $root/lib/libutil -I $root/lib/libtls"

scratch="$(mktemp -d "$obsd/bytetest.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

bison_available=0
command -v bison >/dev/null 2>&1 && bison_available=1

# $1 = daemon source dir; bison is not always on the host, so fall back to
# an Alpine container (the same distro build.sh uses).
run_bison() {
	if [ "$bison_available" = 1 ]; then
		( cd "$1" && bison -d -o "$scratch/y.tab.c" parse.y ) 2>"$scratch/bison.err"
	else
		docker run --rm -v "$1":/p -w /p alpine:edge \
			sh -c 'apk add --no-cache bison >/dev/null 2>&1 && bison -d -o /tmp/y.tab.c parse.y' 2>"$scratch/bison.err" >/dev/null
	fi
}

pass=0; fail=0

while IFS="$(printf '\t')" read -r name parsey struct header extras idirs; do
	case "$name" in ''|\#*) continue ;; esac

	dir="$root/$(dirname "$parsey")"
	printf '%-12s ' "$name"

	if [ ! -f "$root/$parsey" ]; then
		echo "bison: MISSING $parsey"
		fail=$((fail+1)); continue
	fi
	if ! run_bison "$dir"; then
		echo "bison: failed on $parsey:"
		sed 's/^/        /' "$scratch/bison.err" | head -4
		fail=$((fail+1)); continue
	fi

	probe="$scratch/${name}.c"
	{
		printf '#include <stdint.h>\n#include <sys/socket.h>\n#include <net/if.h>\n#include <netinet/in.h>\n'
		if [ "$extras" != "-" ]; then
			oldIFS=$IFS; IFS=';'
			for h in $extras; do printf '#include <%s>\n' "$h"; done
			IFS=$oldIFS
		fi
		printf '#include "%s"\n' "$(basename "$header")"
		printf '#include <stdio.h>\nint main(void){ printf("%%s = %%zu\\n", "%s", sizeof(%s)); return 0; }\n' \
			"$struct" "$struct"
	} > "$probe"

	inc="$common_inc -I $root/$(dirname "$header")"
	if [ "$idirs" != "-" ]; then
		oldIFS=$IFS; IFS=':'
		for d in $idirs; do inc="$inc -I $d"; done
		IFS=$oldIFS
	fi

	if gcc -w $inc "$probe" -o "$scratch/${name}.dump" 2>"$scratch/${name}.err"; then
		printf 'conf %-24s ' "$struct"
		"$scratch/${name}.dump"
		pass=$((pass+1))
	else
		echo "sizeof: header did not compile:"
		sed 's/^/        /' "$scratch/${name}.err" | head -4
		fail=$((fail+1))
	fi
done < "$here/daemons.tsv"

echo
echo "bytetest: $pass ok, $fail failed"
[ "$fail" = 0 ]
