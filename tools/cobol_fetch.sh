#!/bin/sh
# Fetches GnuCOBOL 3.2's source into bench/cache/cobol (not in the repository) and unpacks the two files
# the COBOL work reads: cobc/reserved.c (tools/cobol_reserved.py makes corpus/cobol/reserved.hbnf from it) and
# cobc/parser.y (its yacc grammar, to be counted against corpus/cobol/cobol.hbnf).  The hash is that of the
# tarball as first fetched, 2026-10-31.
#   sh tools/cobol_fetch.sh
set -eu
cd "$(dirname "$0")/.."
URL=https://ftp.gnu.org/gnu/gnucobol/gnucobol-3.2.tar.xz
SHA=3bb48af46ced4779facf41fdc2ee60e4ccb86eaa99d010b36685315df39c2ee2
D=bench/cache/cobol
mkdir -p "$D/src"
if [ ! -f "$D/gnucobol-3.2.tar.xz" ]; then
	curl -fsSL -o "$D/gnucobol-3.2.tar.xz.part" "$URL"
	mv "$D/gnucobol-3.2.tar.xz.part" "$D/gnucobol-3.2.tar.xz"
fi
echo "$SHA  $D/gnucobol-3.2.tar.xz" | sha256sum -c - > /dev/null || { echo "cobol_fetch: the tarball is not the one pinned" >&2; exit 1; }
tar -xJf "$D/gnucobol-3.2.tar.xz" -C "$D/src" --strip-components=1 gnucobol-3.2/cobc/reserved.c gnucobol-3.2/cobc/parser.y
echo "cobol_fetch: $D/src/cobc/reserved.c and parser.y"
