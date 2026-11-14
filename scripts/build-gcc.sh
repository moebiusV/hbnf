#!/bin/sh
# Build a gcc (C only: the driver and cc1, all that `-E` and `-fsyntax-only` need) to compare the C preprocessor and the C grammars with.
#   sh scripts/build-gcc.sh [VERSION [PREFIX]]       default 16.2.0 into $HOME/hbnf-build/gcc16/inst
# then:  GCC=PREFIX/bin/gcc sh tests/cpp.sh      python3 scripts/cpp-scan.py --gcc PREFIX/bin/gcc DIR...      PATH=PREFIX/bin:$PATH sh tests/c99.sh
# Resumable (each step skips what is done); the source is checked against the sha512 of the release.  It takes a while (about 20 minutes on 12 cores).
set -eu
V=${1:-16.2.0}
ROOT=${HOME}/hbnf-build/gcc${V%%.*}
PREFIX=${2:-$ROOT/inst}
mkdir -p "$ROOT" && cd "$ROOT"
[ -f gcc-$V.tar.xz ] || curl -fsSL -o gcc-$V.tar.xz https://ftp.gnu.org/gnu/gcc/gcc-$V/gcc-$V.tar.xz
curl -fsSL -o sha512.sum https://sourceware.org/pub/gcc/releases/gcc-$V/sha512.sum
grep " gcc-$V.tar.xz\$" sha512.sum > want.sum
sha512sum -c want.sum
[ -d gcc-$V ] || tar xf gcc-$V.tar.xz
( cd gcc-$V && { [ -d gmp ] || [ -d mpfr ] || ./contrib/download_prerequisites; } )
mkdir -p obj && cd obj
[ -f Makefile ] || ../gcc-$V/configure --prefix="$PREFIX" --enable-languages=c --disable-multilib --disable-bootstrap --disable-nls --disable-libsanitizer \
	--disable-libquadmath --disable-libgomp --disable-libatomic --disable-libssp --disable-libvtv --disable-lto --disable-plugin --disable-checking --without-isl
make -j"${JOBS:-6}" all-gcc
make install-gcc
echo "gcc $V is in $PREFIX/bin/gcc; tools/gen_gcc_tables.py $PREFIX/bin/gcc makes corpus/c/cpp-gnu.hbnf from it"
