#!/bin/sh
# lib/hbnf_sum.h against published values: SHA-256, the CRCs, Adler-32, the
# Internet checksum, and bech32/bech32m.
#   sh tests/sum.sh
set -u
CC=${CC:-gcc}
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
$CC -std=c99 -Wall -Wextra -Werror -Ilib -o "$T/sum" tests/sum_main.c || { echo "FAIL cc"; exit 1; }
"$T/sum" > "$T/out"; rc=$?
cat "$T/out"
[ $rc -eq 0 ] && echo "sum OK" || { echo "sum: FAIL"; exit 1; }
