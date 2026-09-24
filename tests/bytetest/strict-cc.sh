#!/bin/sh
# strict-cc.sh ROOT DAEMON_DIR FILE.c...: compile generated C the way the
# daemon's own sources are built, and fail on any warning in it.
#
#   - the -W flags from the daemon's Makefile (CFLAGS+= lines);
#   - plus the errors gcc 14 and clang make of implicit declarations and
#     pointer/integer mismatches, which older gcc only warns about (the
#     harness builds everything else with -w, so it would not see them);
#   - with every compiler present: gcc, and clang (OpenBSD's compiler).
#
# Only warnings located in the generated files (in FILE's directory) count:
# OpenBSD's headers warn on Linux (gcc does not know `bounded`).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root=$1; dir=$2; shift 2
wflags=$(sed -n 's/^CFLAGS+=//p' "$dir/Makefile" | grep -o -- '-W[^ ]*' | tr '\n' ' ')
strict="-Werror=implicit-function-declaration -Werror=incompatible-pointer-types \
	-Werror=int-conversion -Werror=return-type"
# The daemon's directory first, as its Makefile's -I${.CURDIR}: its
# "log.h" is not libevent's.
inc="-I $dir -I $here/bsdinc -I $root/include -I $root/lib/libc/include \
	-I $root/sys -I $root/sys/arch/amd64/include \
	-I $root/lib/libevent -I $root/lib/libutil -I $root/lib/libtls"
rc=0
for cc in gcc clang; do
	command -v $cc >/dev/null 2>&1 || continue
	case $cc in
	clang) sys="$(clang -print-resource-dir)/include" ;;
	*)     sys="$($cc -print-file-name=include)" ;;
	esac
	for src in "$@"; do
		d=$(cd "$(dirname "$src")" && pwd); b=$(basename "$src" .c)
		log="$d/$b.$cc.log"
		if ! $cc -std=gnu11 $wflags $strict -nostdinc -isystem "$sys" $inc \
			-I "$d" -c "$d/$b.c" -o /dev/null 2> "$log"; then
			echo "  $cc: $b.c does not compile"; grep -m5 'error' "$log"; rc=1
			continue
		fi
		own=$(grep -E "^$d/[^:]*:[0-9]+:[0-9]+: warning" "$log" || true)
		if [ -n "$own" ]; then
			echo "  $cc: $b.c: $(printf '%s\n' "$own" | wc -l | tr -d ' ') warnings"
			printf '%s\n' "$own" | sed "s#^$d/##" | head -10; rc=1
		else
			echo "  $cc: $b.c: no warnings ($wflags)"
		fi
	done
done
exit $rc
