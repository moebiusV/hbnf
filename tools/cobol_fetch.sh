#!/bin/sh
# Fetches GnuCOBOL 3.2's source into bench/cache/cobol (not in the repository) and unpacks what the COBOL work reads:
# cobc/reserved.c (tools/cobol_reserved.py makes corpus/cobol/reserved.hbnf from it), cobc/parser.y (its yacc
# grammar, to be counted against corpus/cobol/cobol.hbnf) and the test suite, tests/testsuite.src, whose programs
# tools/cobol_extract.py writes out as free-format files (bench/cache/cobol/programs) for scripts/cobol-scan.sh.  The hashes are those of
# the tarballs as first fetched, 2026-10-31 and 2026-11-03.
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
mkdir -p "$D/tests"
tar -xJf "$D/gnucobol-3.2.tar.xz" -C "$D/tests" gnucobol-3.2/tests/testsuite.src
python3 tools/cobol_extract.py "$D/tests/gnucobol-3.2/tests/testsuite.src" "$D/programs"
# The NIST COBOL-85 validation suite (public domain), as GnuCOBOL's site keeps it, and the configuration GnuCOBOL's own tests give it
# (tests/cobol85/EXEC85.conf.in): tools/cobol_extract_nist.py writes its 459 programs as free-format files (bench/cache/cobol/nist).
NIST_URL=https://gnucobol.sourceforge.io/files/newcob.val.tar.gz
NIST_SHA=e4513f26a9b38911f7bf882fe3d3339a80b45cabc2caf85eb3055b0f5ce87ee0
if [ ! -f "$D/newcob.val.tar.gz" ]; then
	curl -fsSL -o "$D/newcob.val.tar.gz.part" "$NIST_URL"
	mv "$D/newcob.val.tar.gz.part" "$D/newcob.val.tar.gz"
fi
echo "$NIST_SHA  $D/newcob.val.tar.gz" | sha256sum -c - > /dev/null || { echo "cobol_fetch: the NIST archive is not the one pinned" >&2; exit 1; }
mkdir -p "$D/nist-src"
tar -xzf "$D/newcob.val.tar.gz" -C "$D/nist-src"
tar -xJf "$D/gnucobol-3.2.tar.xz" -C "$D/tests" gnucobol-3.2/tests/cobol85/EXEC85.conf.in
python3 tools/cobol_extract_nist.py "$D/nist-src/newcob.val" "$D/tests/gnucobol-3.2/tests/cobol85/EXEC85.conf.in" "$D/nist"
echo "cobol_fetch: $D/src/cobc/reserved.c and parser.y, the tests in $D/tests, the programs in $D/programs and $D/nist"
