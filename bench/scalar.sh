#!/bin/sh
# scalar.sh -- the number and string conversions of runtime/hbnf_scalar.h against fast_float (what simdjson converts
# doubles with) and glibc's strtod.  Writes bench/results/scalar.md.
#
#   sh bench/scalar.sh        (host; needs docker)
#
# fast_float is the single-header release pinned in pins.txt.  Each figure is the best of three runs of the best of
# many passes, in nanoseconds a number; pinned to one cpu like the others.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/pins.txt"
mkdir -p "$here/cache/scalar"
[ -f "$here/cache/scalar/fast_float.h" ] || curl -sL -o "$here/cache/scalar/fast_float.h" "$FASTFLOAT_URL"
echo "$FASTFLOAT_SHA  $here/cache/scalar/fast_float.h" | sha256sum -c - > /dev/null || { echo "scalar.sh: fast_float.h does not match pins.txt" >&2; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; chmod 777 "$W"
docker build -q -t hbnf-libs-glibc -f "$here/libs/Dockerfile.glibc" "$here/libs" > /dev/null
docker run --rm --cpuset-cpus="${BENCH_CPUS:-5}" --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/w:ro" -v "$W:/o" \
	hbnf-libs-glibc sh /w/bench/scalar/inner.sh > "$W/out.txt"
rev=$(git -C "$root" rev-parse --short HEAD 2> /dev/null || echo unknown)
python3 - "$W/out.txt" "$rev" > "$here/results/scalar.md" <<'PY'
import sys, collections
best = {}
unesc = {}
order = []
for l in open(sys.argv[1]):
    p = l.strip().split('|')
    if p[0] == 'unescape':
        k = p[1]; v = (float(p[2]), float(p[3]))
        old = unesc.get(k, (0, 0)); unesc[k] = (max(old[0], v[0]), max(old[1], v[1]))
    else:
        k = (p[0], p[1]); v = float(p[2])
        if p[0] not in order: order.append(p[0])
        best[k] = min(best.get(k, 1e18), v)
print("**Numbers**, nanoseconds each (best of three runs; the same text for each tool):\n")
print("| numbers | hbnf_scalar.h | fast_float | glibc strtod |")
print("|---|---:|---:|---:|")
for s in order:
    print(f"| {s} | {best[(s,'hbnf_parse_number')]:.1f} ns | {best[(s,'fast_float')]:.1f} ns | {best[(s,'strtod')]:.1f} ns |")
print("\n**Strings**, GB/s of input (one 64 KiB string):\n")
print("| string | hbnf_unescape | a byte loop |")
print("|---|---:|---:|")
for k, (a, b) in unesc.items():
    print(f"| {k} | {a:.1f} GB/s | {b:.1f} GB/s |")
print(f"\n_{__import__('datetime').date.today()}; gcc -O2, glibc; fast_float v6.1.6; hbnf {sys.argv[2]}.  The integers go through `strtoll` in the last column.  fast_float reads an integer as a `long long`, and a decimal as a `double`._")
PY
cat "$here/results/scalar.md"
