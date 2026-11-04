#!/bin/sh
# libs.sh -- JSON, TOML, YAML and XML: the parsers hbnf makes against the libraries people use for
# each format, on glibc (Debian), with the same sources and flags.  Writes bench/results/libs.md.
#
#   HBNF=/path/to/hbnf sh bench/libs.sh        (host; needs docker)
#
# Which libraries: the popular native ones for each format, by GitHub stars and package
# downloads as the author judged them, limited to what Debian packages or is a single file
# pinned in pins.txt (rapidyaml, tomlc17); and the parsers the scripting languages ship or
# their programs use (Python's json, tomllib and PyYAML, Node's JSON.parse and js-yaml).  For XML:
# expat, libxml2, pugixml, TinyXML-2 and RapidXML (all Debian packages), Python's ElementTree, lxml
# and pyexpat, and Node's fast-xml-parser and sax (bench/libs/node/package-lock.json).  The
# documents are made by bench/formats/gen.py: a list of records with strings, numbers, booleans,
# lists and a nested table; for XML a product catalog.
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

echo "$XMLJS_LOCK_SHA  $here/libs/node/package-lock.json" | sha256sum -c - > /dev/null || { echo "libs.sh: node/package-lock.json does not match pins.txt" >&2; exit 1; }

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; chmod 755 "$W"
for n in json toml yaml xml; do python3 "$here/formats/gen.py" $n 2000000 > "$W/doc.$n"; done

# hbnf's parsers: the generator only writes C, so its own libc does not matter here
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e HBNF_TEMPLATES=/w/templates \
	-v "$root:/w:ro" -v "$W:/o" -v "$(dirname "$hb"):/hbnf-bin:ro" ada-toolchain:edge-full sh -c '
	for spec in json:json toml:toml yaml:yaml xml:document; do
		n=${spec%%:*}; r=${spec##*:}
		/hbnf-bin/'"$(basename "$hb")"' /w/corpus/$n/$n.hbnf --backend=c --root=$r > /o/$n.c
	done
	/hbnf-bin/'"$(basename "$hb")"' /w/corpus/json/json-tape.hbnf --backend=c --root=json > /o/json-tape.c
	/hbnf-bin/'"$(basename "$hb")"' /w/corpus/toml/toml-tape.hbnf --backend=c --root=toml > /o/toml-tape.c
	/hbnf-bin/'"$(basename "$hb")"' /w/corpus/yaml/yaml-tape.hbnf --backend=c --root=yaml > /o/yaml-tape.c
	/hbnf-bin/'"$(basename "$hb")"' /w/corpus/xml/xml.hbnf --backend=c --layout=tape --root=document > /o/xml-tape.c'

docker build -q -t hbnf-libs-glibc -f "$here/libs/Dockerfile.glibc" "$here/libs" > /dev/null
mkdir -p "$W/glibc"; chmod 777 "$W/glibc"
cp "$W"/doc.* "$W"/json.c "$W"/json-tape.c "$W"/toml-tape.c "$W"/yaml-tape.c "$W"/xml-tape.c "$W"/toml.c "$W"/yaml.c "$W"/xml.c "$W/glibc/"
docker run --rm --cpuset-cpus="${BENCH_CPUS:-5}" --user "$(id -u):$(id -g)" -e RUNS="$RUNS" -v "$root:/w:ro" -v "$W/glibc:/o" \
	hbnf-libs-glibc sh /w/bench/libs/inner.sh > "$W/glibc.tsv"
docker run --rm hbnf-libs-glibc sh -c 'gcc --version | head -1; ldd --version | head -1; node --version; python3 --version; cargo --version; dpkg-query -W -f "\${Package}=\${Version}\n" libexpat1-dev libxml2-dev libpugixml-dev libtinyxml2-dev librapidxml-dev python3-lxml; for p in fast-xml-parser sax; do echo $p=$(node -p "require(\"/opt/js-xml/node_modules/$p/package.json\").version"); done' > "$W/glibc.ver" || true
[ -f "$here/libs/rust/Cargo.lock" ] || cp "$W/glibc/rust/Cargo.lock" "$here/libs/rust/Cargo.lock"

python3 "$here/libs/table.py" "$W" "$root" "$here/libs/rust/Cargo.lock" "$RUNS" > "$here/results/libs.md"
cat "$here/results/libs.md"
sh "$here/update-docs.sh"
