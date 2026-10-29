#!/bin/sh
# haskell.sh -- JSON, TOML and YAML: the parsers Haskell programs use, built with Alex and Happy where
# that is how they are made, beside the hbnf tape parsers.  amd64, glibc (Debian).  Writes
# bench/results/haskell.md.
#
#   HBNF=/path/to/hbnf sh bench/haskell.sh        (host; needs docker)
#
# The Haskell toolchain, toml-parser, HsYAML, yaml and aeson are Debian packages.  toml-parser's source
# is pinned in pins.txt: its Alex lexer and Happy parser are built again with the generators in their
# optimising modes.  The JSON grammar in Alex and Happy is written here, in two forms (the way the
# tutorials write one, and tuned), because no complete one is published; no YAML parser in Alex and Happy
# is known, so YAML is HsYAML, which is pure Haskell, and the libyaml-based yaml package.  Every
# parser is asked about the good and bad files of the format's corpus before it is timed, and the
# timing runs on one cpu (BENCH_CPUS, default logical cpu 5), as the other rigs' do.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/pins.txt"
hb=${HBNF:-$root/hbnf}
RUNS=${RUNS:-5}
[ "$(uname -m)" = x86_64 ] || { echo "haskell.sh: amd64 only, as the other benchmarks" >&2; exit 1; }

mkdir -p "$here/cache/haskell"
tp="$here/cache/haskell/toml-parser.tar.gz"
[ -f "$tp" ] || curl -sL -o "$tp" "$TOMLPARSER_URL"
echo "$TOMLPARSER_SHA  $tp" | sha256sum -c - > /dev/null || { echo "haskell.sh: toml-parser does not match pins.txt" >&2; exit 1; }

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; chmod 755 "$W"
for n in json toml yaml; do python3 "$here/formats/gen.py" $n 2000000 > "$W/doc.$n"; done
cp "$tp" "$W/toml-parser.tar.gz"

# the hbnf tape parsers, generated as bench/libs.sh generates them
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e HBNF_TEMPLATES=/w/templates \
	-v "$root:/w:ro" -v "$W:/o" -v "$(dirname "$hb"):/hbnf-bin:ro" ada-toolchain:edge-full sh -c '
	for n in json toml yaml; do
		/hbnf-bin/'"$(basename "$hb")"' /w/corpus/$n/$n-tape.hbnf --backend=c --root=$n > /o/$n-tape.c
	done'

docker build -q -t hbnf-haskell-glibc -f "$here/haskell/Dockerfile.glibc" "$here/haskell" > /dev/null
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/w:ro" -v "$W:/o" \
	hbnf-haskell-glibc sh /w/bench/haskell/build.sh > "$W/build.out" 2>&1 \
	|| { echo "haskell.sh: the build failed" >&2; tail -20 "$W/build.out" >&2; exit 1; }
docker run --rm --cpuset-cpus="${BENCH_CPUS:-5}" --user "$(id -u):$(id -g)" -e HOME=/tmp -e RUNS="$RUNS" \
	-v "$root:/w:ro" -v "$W:/o" hbnf-haskell-glibc sh /w/bench/haskell/inner.sh > "$W/haskell.tsv"
docker run --rm hbnf-haskell-glibc sh -c 'ghc --version; alex --version | head -1; happy --version | head -1' > "$W/haskell.ver"

python3 "$here/haskell/table.py" "$W" "$RUNS" "$root" > "$here/results/haskell.md"
cat "$here/results/haskell.md"
sh "$here/update-docs.sh"
