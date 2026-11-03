#!/bin/sh
# raku.sh -- JSON, TOML and YAML: the parsers Raku programs use, beside the hbnf tape parsers.  amd64, glibc
# (Debian).  Writes bench/results/raku.md.
#
#   HBNF=/path/to/hbnf sh bench/raku.sh        (host; needs docker and the network)
#
# Rakudo, zef and JSON::Fast (hand-written Raku) are Debian packages.  The grammar-based modules, JSON::Tiny, TOML
# and YAMLish, are the ecosystem's tarballs pinned in pins.txt; zef also fetches their own dependencies, unpinned
# (YAMLish wants MIME::Base64).  Every parser is asked about the good and bad files of the format's corpus before it
# is timed, and the timing runs on one cpu (BENCH_CPUS, default logical cpu 5), as the other rigs' do.  A parse
# that takes more than 20 s is run once, and one that takes more than RAKU_TIMEOUT (900 s) is stopped.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/pins.txt"
hb=${HBNF:-$root/hbnf}
RUNS=${RUNS:-5}
[ "$(uname -m)" = x86_64 ] || { echo "raku.sh: amd64 only, as the other benchmarks" >&2; exit 1; }

mkdir -p "$here/cache/raku"
fetch() {   # fetch NAME URL SHA
	f="$here/cache/raku/$1.tar.gz"
	[ -f "$f" ] || curl -sL -o "$f" "$2"
	echo "$3  $f" | sha256sum -c - > /dev/null || { echo "raku.sh: $1 does not match pins.txt" >&2; exit 1; }
}
fetch jsontiny "$RAKU_JSONTINY_URL" "$RAKU_JSONTINY_SHA"
fetch toml "$RAKU_TOML_URL" "$RAKU_TOML_SHA"
fetch yamlish "$RAKU_YAMLISH_URL" "$RAKU_YAMLISH_SHA"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; chmod 755 "$W"
for n in json toml yaml; do python3 "$here/formats/gen.py" $n 2000000 > "$W/doc.$n"; done
# the tarballs of JSON::Tiny and YAMLish have a top directory; TOML's has none
mkdir -p "$W/src/jsontiny" "$W/src/toml" "$W/src/yamlish"
tar xzf "$here/cache/raku/jsontiny.tar.gz" -C "$W/src/jsontiny" --strip-components=1
tar xzf "$here/cache/raku/toml.tar.gz" -C "$W/src/toml"
tar xzf "$here/cache/raku/yamlish.tar.gz" -C "$W/src/yamlish" --strip-components=1

# the hbnf tape parsers, generated as bench/libs.sh generates them
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e HBNF_TEMPLATES=/w/templates \
	-v "$root:/w:ro" -v "$W:/o" -v "$(dirname "$hb"):/hbnf-bin:ro" ada-toolchain:edge-full sh -c '
	for n in json toml yaml; do
		/hbnf-bin/'"$(basename "$hb")"' /w/corpus/$n/$n-tape.hbnf --backend=c --root=$n > /o/$n-tape.c
	done'

docker build -q -t hbnf-raku-glibc -f "$here/raku/Dockerfile.glibc" "$here/raku" > /dev/null
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/w:ro" -v "$W:/o" \
	hbnf-raku-glibc sh /w/bench/raku/build.sh > "$W/build.out" 2>&1 \
	|| { echo "raku.sh: the build failed" >&2; tail -20 "$W/build.out" >&2; exit 1; }
docker run --rm --cpuset-cpus="${BENCH_CPUS:-5}" --user "$(id -u):$(id -g)" -e HOME=/tmp -e RUNS="$RUNS" \
	-v "$root:/w:ro" -v "$W:/o" hbnf-raku-glibc sh /w/bench/raku/inner.sh > "$W/raku.tsv"
docker run --rm hbnf-raku-glibc sh -c 'raku --version | head -1' > "$W/raku.ver"

python3 "$here/raku/table.py" "$W" "$RUNS" "$root" > "$here/results/raku.md"
cat "$here/results/raku.md"
sh "$here/update-docs.sh"
