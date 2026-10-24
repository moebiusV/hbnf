#!/bin/sh
# libs.sh -- JSON, TOML and YAML: the parsers hbnf makes against the popular native libraries for
# each format, built and timed twice, against musl (Alpine) and against glibc (Debian), with
# the same sources and flags.  Writes bench/results/libs.md.
#
#   HBNF=/path/to/hbnf sh bench/libs.sh        (host; needs docker)
#
# Which libraries: chosen by GitHub stars and package downloads, as the author judged them,
# and limited to what is packaged for both Alpine and Debian or is a single file that pins in
# pins.txt (rapidyaml, tomlc17).  The documents are those of stage-formats.sh.
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
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e HBNF_TEMPLATES=/w/templates \
	-v "$root:/w:ro" -v "$W:/o" -v "$(dirname "$hb"):/hbnf-bin:ro" hbnf-bench sh -c '
	for spec in json:json toml:toml yaml:yaml; do
		n=${spec%%:*}; r=${spec##*:}
		/hbnf-bin/'"$(basename "$hb")"' /w/corpus/$n/$n.hbnf --backend=c --root=$r > /o/$n.c
	done'

for libc in musl glibc; do
	docker build -q -t hbnf-libs-$libc -f "$here/libs/Dockerfile.$libc" "$here/libs" > /dev/null
	mkdir -p "$W/$libc"; chmod 777 "$W/$libc"
	cp "$W"/doc.* "$W"/json.c "$W"/toml.c "$W"/yaml.c "$W/$libc/"
	docker run --rm --user "$(id -u):$(id -g)" -e RUNS="$RUNS" -v "$root:/w:ro" -v "$W/$libc:/o" \
		hbnf-libs-$libc sh /w/bench/libs/inner.sh > "$W/$libc.tsv"
	docker run --rm hbnf-libs-$libc sh -c 'gcc --version | head -1; ldd --version 2>&1 | head -1' > "$W/$libc.ver" || true
done
[ -f "$here/libs/rust/Cargo.lock" ] || cp "$W/glibc/rust/Cargo.lock" "$here/libs/rust/Cargo.lock"

python3 - "$W" "$root" "$here/libs/rust/Cargo.lock" "$RUNS" <<'PYEOF' > "$here/results/libs.md"
import sys, re, datetime, subprocess
W, root, lock, runs = sys.argv[1:5]
def rows(libc):
    out = {}
    for l in open(f"{W}/{libc}.tsv"):
        f, lab, ms, rss, st = l.rstrip("\n").split("\t")
        out.setdefault(f, []).append((lab, float(ms), int(rss), st))
    return out
m, g = rows("musl"), rows("glibc")
vers = dict(re.findall(r'name = "([^"]+)"\nversion = "([^"]+)"', open(lock).read()))
titles = {"json": "JSON", "toml": "TOML 1.0", "yaml": "YAML 1.2"}
def fmt(ms): return "%.1f ms" % ms if ms < 10 else "%.0f ms" % ms
for f in ("json", "toml", "yaml"):
    print(f"**{titles[f]}** (2 MB, the same file for every tool; parse time, best of {runs}):\n")
    print("| tool | musl | glibc | peak RSS (glibc) |\n|---|---:|---:|---:|")
    gl = {lab: (ms, rss, st) for lab, ms, rss, st in g[f]}
    order = sorted(m[f], key=lambda r: (r[3] != "ok", gl.get(r[0], (1e9,))[0]))
    for lab, ms, rss, st in order:
        if lab.startswith("serde_json"): lab += " " + vers.get("serde_json", "")
        if lab.startswith("toml (Rust)"): lab += " " + vers.get("toml", "")
        gm = gl.get(lab.split(" 1")[0].split(" 0")[0], gl.get(lab, (0, 0, "?")))
        if st != "ok" or gm[2] != "ok":
            print(f"| {lab} | {st if st != 'ok' else 'ok'} | {gm[2] if gm[2] != 'ok' else 'ok'} | |")
        else:
            print(f"| {lab} | {fmt(ms)} | {fmt(gm[0])} | {gm[1] // 1024} MB |")
    print()
v = [open(f"{W}/{x}.ver").read().split("\n") for x in ("musl", "glibc")]
print(f"_{datetime.date.today()}; musl: {v[0][1].strip() or 'musl'}, {v[0][0]}; glibc: {v[1][1].split()[-1]}, {v[1][0]}; "
      f"`-O2`, same sources and flags; hbnf {subprocess.check_output(['git','-C',root,'rev-parse','--short','HEAD']).decode().strip()}.  "
      "simdjson is its DOM API; the C++ and Rust libraries build their own value types._")
PYEOF
cat "$here/results/libs.md"
