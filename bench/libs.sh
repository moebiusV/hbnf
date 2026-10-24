#!/bin/sh
# libs.sh -- JSON, TOML and YAML: the parsers hbnf makes against the libraries people use for
# each format, on glibc (Debian), with the same sources and flags.  Writes bench/results/libs.md.
#
#   HBNF=/path/to/hbnf sh bench/libs.sh        (host; needs docker)
#
# Which libraries: the popular native ones for each format, by GitHub stars and package
# downloads as the author judged them, limited to what Debian packages or is a single file
# pinned in pins.txt (rapidyaml, tomlc17); and the parsers the scripting languages ship or
# their programs use (Python's json, tomllib and PyYAML, Node's JSON.parse and js-yaml).  The
# documents are those of stage-formats.sh.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/pins.txt"
hb=${HBNF:-$root/hbnf}
RUNS=${RUNS:-5}

# the two single-file libraries, checked against pins.txt
mkdir -p "$here/cache/libs"
fetch() {   # fetch URL FILE SHA
	[ -f "$here/cache/libs/$2" ] || curl -sL -o "$here/cache/libs/$2" "$1"
	echo "$3  $here/cache/libs/$2" | sha256sum -c - > /dev/null || { echo "libs.sh: $2 does not match pins.txt" >&2; exit 1; }
}
raw=https://raw.githubusercontent.com/cktan/tomlc17/$TOMLC17_COMMIT/src
fetch "$RYML_URL" ryml.hpp "$RYML_SHA"
fetch "$raw/tomlc17.c" tomlc17.c "$TOMLC17_C_SHA"
fetch "$raw/tomlc17.h" tomlc17.h "$TOMLC17_H_SHA"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; chmod 755 "$W"
for n in json toml yaml; do python3 "$here/formats/gen.py" $n 2000000 > "$W/doc.$n"; done

# hbnf's parsers: the generator only writes C, so its own libc does not matter here
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e HBNF_TEMPLATES=/w/templates \
	-v "$root:/w:ro" -v "$W:/o" -v "$(dirname "$hb"):/hbnf-bin:ro" ada-toolchain:edge-full sh -c '
	for spec in json:json toml:toml yaml:yaml; do
		n=${spec%%:*}; r=${spec##*:}
		/hbnf-bin/'"$(basename "$hb")"' /w/corpus/$n/$n.hbnf --backend=c --root=$r > /o/$n.c
	done'

docker build -q -t hbnf-libs-glibc -f "$here/libs/Dockerfile.glibc" "$here/libs" > /dev/null
mkdir -p "$W/glibc"; chmod 777 "$W/glibc"
cp "$W"/doc.* "$W"/json.c "$W"/toml.c "$W"/yaml.c "$W/glibc/"
docker run --rm --user "$(id -u):$(id -g)" -e RUNS="$RUNS" -v "$root:/w:ro" -v "$W/glibc:/o" \
	hbnf-libs-glibc sh /w/bench/libs/inner.sh > "$W/glibc.tsv"
docker run --rm hbnf-libs-glibc sh -c 'gcc --version | head -1; ldd --version | head -1; node --version; python3 --version; cargo --version' > "$W/glibc.ver" || true
[ -f "$here/libs/rust/Cargo.lock" ] || cp "$W/glibc/rust/Cargo.lock" "$here/libs/rust/Cargo.lock"

python3 "$here/libs/table.py" "$W" "$root" "$here/libs/rust/Cargo.lock" "$RUNS" > "$here/results/libs.md"
cat "$here/results/libs.md"
