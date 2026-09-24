#!/bin/sh
# Keyword parity: each daemon grammar's `keywords { ... }` table must be the
# words its parse.y's lookup() reserves, no more and no fewer.  A word hbnf
# reserves and parse.y doesn't rejects a config parse.y accepts (`set
# loginterface none`); the other way round accepts one it rejects.
#   OBSD=/path/to/obsd79 sh tests/bytetest/keywords.sh
# Needs the extracted OpenBSD tree (see README.md); nothing is compiled.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"                        # sources/hbnf
obsd="${OBSD:-$(cd "$here/../../../.." && pwd)/.work/obsd79}"
root="$obsd/extracted"
[ -d "$root/usr.sbin" ] || { echo "keywords: no OpenBSD tree at $root (set OBSD=)" >&2; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
rc=0
for pair in pfctl:sbin/pfctl bgpd:usr.sbin/bgpd relayd:usr.sbin/relayd \
            httpd:usr.sbin/httpd ntpd:usr.sbin/ntpd snmpd:usr.sbin/snmpd \
            ldpd:usr.sbin/ldpd unwind:sbin/unwind dhcpleased:sbin/dhcpleased; do
	g=${pair%%:*}; y="$root/${pair#*:}/parse.y"
	awk '/^lookup\(char \*s\)/{f=1} f&&/^}/{f=0} f' "$y" \
	    | grep -oE '\{[[:space:]]*"[^"]+",[[:space:]]*[A-Z0-9_]+[[:space:]]*\}' \
	    | sed -E 's/^\{[[:space:]]*"([^"]+)".*/\1/' | sort > "$W/y"
	awk '/^keywords[[:space:]]*\{/{f=1;next} f&&/^\}/{f=0} f' "$repo/grammars/$g.hbnf" \
	    | sed 's/;.*//' | tr -s ' \t' '\n\n' | grep -v '^$' | sort > "$W/h"
	if cmp -s "$W/y" "$W/h"; then
		echo "$g: OK ($(wc -l < "$W/y" | tr -d ' ') keywords)"
	else
		echo "$g: DIFFER"; rc=1
		comm -13 "$W/y" "$W/h" | sed 's/^/  hbnf only: /'
		comm -23 "$W/y" "$W/h" | sed 's/^/  parse.y only: /'
	fi
done
exit $rc
