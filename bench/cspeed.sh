#!/bin/sh
# cspeed.sh -- the C parser's speed: the generated C11 parser (the typed tree, corpus/c/c11.hbnf) and
# `gcc -fsyntax-only` over the same preprocessed C, pinned to one cpu.  Writes bench/results/cspeed.md.
#
#   HBNF=/path/to/hbnf sh bench/cspeed.sh        (host; needs docker)
#
# The sources are pinned in pins.txt (Lua, zlib, the SQLite amalgamation).  Each .c is preprocessed with
# gcc -E -P (hbnf has no preprocessor) and kept if gcc -fsyntax-only accepts it; both tools then read the
# same files.  gcc also checks types, which a grammar does not, so the comparison favours the parser.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/pins.txt"
hb=${HBNF:-$root/hbnf}
RUNS=${RUNS:-5}

mkdir -p "$here/cache/cspeed"
fetch() {   # fetch URL FILE SHA
	[ -f "$here/cache/cspeed/$2" ] || curl -sL -o "$here/cache/cspeed/$2" "$1"
	echo "$3  $here/cache/cspeed/$2" | sha256sum -c - > /dev/null || { echo "cspeed.sh: $2 does not match pins.txt" >&2; exit 1; }
}
fetch "$CSPEED_LUA_URL" lua.tgz "$CSPEED_LUA_SHA"
fetch "$CSPEED_ZLIB_URL" zlib.tgz "$CSPEED_ZLIB_SHA"
fetch "$CSPEED_SQLITE_URL" sqlite.zip "$CSPEED_SQLITE_SHA"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; chmod 755 "$W"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e HBNF_TEMPLATES=/w/templates \
	-v "$root:/w:ro" -v "$W:/o" -v "$(dirname "$hb"):/hbnf-bin:ro" ada-toolchain:edge-full sh -c '
	/hbnf-bin/'"$(basename "$hb")"' /w/corpus/c/c11.hbnf --backend=c > /o/c11.c'
docker build -q -t hbnf-libs-glibc -f "$here/libs/Dockerfile.glibc" "$here/libs" > /dev/null
mkdir -p "$W/glibc"; chmod 777 "$W/glibc"
cp "$W/c11.c" "$here"/cache/cspeed/lua.tgz "$here"/cache/cspeed/zlib.tgz "$here"/cache/cspeed/sqlite.zip "$W/glibc/"
docker run --rm --cpuset-cpus="${BENCH_CPUS:-5}" --user "$(id -u):$(id -g)" -e HOME=/tmp -e RUNS="$RUNS" \
	-v "$root:/w:ro" -v "$W/glibc:/o" hbnf-libs-glibc sh /w/bench/cspeed/inner.sh > "$W/out.txt"
ver=$(docker run --rm hbnf-libs-glibc sh -c 'gcc --version | head -1; ldd --version | head -1' | tr '\n' ';')
rev=$(git -C "$root" rev-parse --short HEAD 2> /dev/null || echo unknown)
python3 - "$W/out.txt" "$ver" "$rev" "$RUNS" > "$here/results/cspeed.md" <<'PY'
import sys
kv={}
for l in open(sys.argv[1]):
    k,_,v=l.strip().partition(' '); kv[k]=v
ms,by,ref,rss=kv['hbnf'].split()
ms,by=float(ms),int(by); gms=float(kv['gcc']); mb=by/1e6
bigsize,bigrss=(int(x) for x in kv['big'].split())
print(f"**{kv['files']} translation units, {mb:.1f} MB of preprocessed C** (Lua 5.4.7, zlib 1.3.1, the SQLite 3.45.1 amalgamation; best of {sys.argv[4]} runs):\n")
print("| tool | time | MB/s | peak memory, the largest unit alone |")
print("|---|---:|---:|---:|")
print(f"| hbnf (C backend), the C11 grammar, typed tree | {ms/1000:.2f} s | {mb/(ms/1000):.1f} MB/s | {bigrss/1024:.0f} MB ({bigsize/1e6:.1f} MB of C) |")
print(f"| `gcc -fsyntax-only` | {gms/1000:.2f} s | {mb/(gms/1000):.1f} MB/s | |")
if int(ref): print(f"\nThe parser refused {ref} of the units.")
print(f"\n_{__import__('datetime').date.today()}; {sys.argv[2]} `-O2`; hbnf {sys.argv[3]}.  `gcc -fsyntax-only` also checks types and starts once for each file; the parser reads the whole tree into memory._")
PY
cat "$here/results/cspeed.md"
sh "$here/update-docs.sh"
