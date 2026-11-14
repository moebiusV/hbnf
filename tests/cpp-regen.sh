#!/bin/sh
# Make the expectation of a test file of tests/cpp again from gcc: sh tests/cpp-regen.sh tests/cpp/NAME.c ...
# The flags are those of its first line (`/* flags: ... */`, default `-undef -nostdinc`).  Look at the result before keeping it: gcc is the authority
# for what a preprocessor gives, and a file made from gcc is only as right as the file is.
set -u
cd "$(dirname "$0")/.."
for f in "$@"; do
	case $f in tests/cpp/diag/*) continue;; esac
	first=$(head -1 "$f")
	flags=$(printf '%s' "$first" | sed -n 's|^/\* flags: \(.*\) \*/.*$|\1|p'); [ -n "$flags" ] || flags="-undef -nostdinc"
	"${GCC:-gcc}" -E -P -w $flags "$f" | python3 tools/cpp_tokens.py > "${f%.c}.expected" || { echo "gcc refuses $f"; continue; }
	echo "${f%.c}.expected: $(wc -l < "${f%.c}.expected") tokens"
done
# the diagnostics: tests/cpp/diag/NAME.diag are made from gcc 16 (its wording: names in single quotes), as `LINE: kind: message`
for f in "$@"; do
	case $f in tests/cpp/diag/*.c) ;; *) continue;; esac
	"${GCC:-gcc}" -E -P -undef -nostdinc "$f" 2>&1 > /dev/null | sed -n 's/^[^:]*:\([0-9][0-9]*\)\(:[0-9][0-9]*\)\{0,1\}: \(fatal error\|error\|warning\): \(.*\)$/\1: \3: \4/p' \
		| sed 's/: fatal error:/: error:/; s/ \[-W[a-z0-9=+-]*\]$//' | sort -n > "${f%.c}.diag"
	echo "${f%.c}.diag: $(wc -l < "${f%.c}.diag") diagnostics"
done
