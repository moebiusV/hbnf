#!/bin/sh
# xml-conformance.sh -- does each XML parser of the library benchmark refuse what XML 1.0 forbids?  The same
# drivers as bench/libs.sh (bench/libs/*), the inputs of bench/formats/xml_cases.py: 34 documents that each
# break one well-formedness constraint, and 11 well-formed ones that a careless checker might refuse.  Expat,
# with its own checks on, is the reference.
#
# The check is done ONCE and kept, not redone at every benchmark.  Each parser's verdicts are stored in
# bench/results/xml-conformance-verdicts.tsv with a KEY in bench/results/xml-conformance.keys: the case set
# (bench/formats/xml_cases.py) and the parser's version (the Debian package, the Python or Node package),
# and for hbnf its grammar corpus/xml/xml.hbnf and the generator binary.  This script reruns only the parsers whose key changed (a
# library upgrade, a changed grammar or case set) and does nothing when every key matches; bench/libs.sh
# calls it before it builds the table.  Writes bench/results/xml-conformance.{md,tsv}.
#   sh bench/xml-conformance.sh            only what is stale
#   sh bench/xml-conformance.sh --force    everything again
#   HBNF=/path/to/hbnf                     (default ./hbnf)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
hb=${HBNF:-$root/hbnf}
res="$here/results"
force=0; [ "${1:-}" = --force ] && force=1
TOOLS="expat|libxml2 DOM|libxml2 SAX2|pugixml|TinyXML-2|RapidXML|ElementTree|lxml|fast-xml-parser|sax (Node)|hbnf"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; chmod 755 "$W"
python3 "$here/formats/xml_cases.py" "$W/cases"
docker build -q -t hbnf-libs-glibc -f "$here/libs/Dockerfile.glibc" "$here/libs" > /dev/null

# the keys now: versions asked of the image, the hash of the case set, the hash of hbnf's grammar
docker run --rm hbnf-libs-glibc sh -c '
	v() { dpkg-query -W -f="\${Version}" "$1" 2> /dev/null || echo "?"; }
	echo "expat=$(v libexpat1)"; echo "libxml2 DOM=$(v libxml2)"; echo "libxml2 SAX2=$(v libxml2)"
	echo "pugixml=$(v libpugixml-dev)"; echo "TinyXML-2=$(v libtinyxml2-dev)"; echo "RapidXML=$(v librapidxml-dev)"
	echo "ElementTree=$(python3 --version)"; echo "lxml=$(v python3-lxml)"
	echo "fast-xml-parser=$(node -p "require(\"/opt/js-xml/node_modules/fast-xml-parser/package.json\").version")"
	echo "sax (Node)=$(node -p "require(\"/opt/js-xml/node_modules/sax/package.json\").version")"' > "$W/versions.txt"
cases=$(sha256sum "$here/formats/xml_cases.py" | cut -c1-16)
gram=$(cat "$root/corpus/xml/xml.hbnf" | sha256sum | cut -c1-16)
echo "hbnf=grammar $gram, generator $(sha256sum "$hb" | cut -c1-12)" >> "$W/versions.txt"
: > "$W/keys.new"
while IFS= read -r l; do printf '%s\t%s %s\n' "${l%%=*}" "${l#*=}" "$cases" >> "$W/keys.new"; done < "$W/versions.txt"
touch "$res/xml-conformance.keys" "$res/xml-conformance-verdicts.tsv"
stale=""
IFS='|'; for t in $TOOLS; do
	new=$(awk -F'\t' -v t="$t" '$1 == t {print $2}' "$W/keys.new"); old=$(awk -F'\t' -v t="$t" '$1 == t {print $2}' "$res/xml-conformance.keys")
	have=$(awk -F'\t' -v t="$t" '$2 == t' "$res/xml-conformance-verdicts.tsv" | wc -l)
	if [ "$force" = 1 ] || [ "$new" != "$old" ] || [ "$have" -lt 45 ]; then stale="${stale:+$stale|}$t"; fi
done; unset IFS
if [ -z "$stale" ]; then echo "xml-conformance: every parser is current (version and case-set keys match); nothing to run"; exit 0; fi
echo "xml-conformance: running $(echo "$stale" | tr '|' ',')"

HBNF_TEMPLATES="$root/templates" "$hb" "$root/corpus/xml/xml.hbnf" --backend=c > "$W/xml.c"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e "STALE=$stale" -v "$root:/w:ro" -v "$W:/o" hbnf-libs-glibc sh -c '
	set -u; cd /o; L=/w/bench/libs; CC="gcc -O2 -w"; CXX="g++ -O2 -w -std=c++20"
	build() { src=$1; shift; exe=/o/bin-$(basename "$src" | tr . _); case $src in *.cpp) c="$CXX" ;; *) c="$CC" ;; esac
		$c -I"$L" "$L/$src" -o "$exe" "$@" 2> /dev/null || echo "build failed: $src" >&2; }
	want() { case "|$STALE|" in *"|$1|"*) return 0 ;; *) return 1 ;; esac; }
	want expat && build expat.c -lexpat
	{ want "libxml2 DOM" || want "libxml2 SAX2"; } && build libxml2.c $(pkg-config --cflags --libs libxml-2.0)
	want pugixml && build pugixml.cpp -lpugixml
	want TinyXML-2 && build tinyxml2.cpp -ltinyxml2
	want RapidXML && build rapidxml.cpp
	if want hbnf; then t=$(sed -n "s/^bool parse_text(const char \*text, \(.*\) \*out,\$/\1/p" /o/xml.c)
		cat /o/xml.c /w/corpus/c/check.c > /o/xml-m.c; $CC -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$t" /o/xml-m.c -o /o/bin-hbnf 2> /dev/null || echo "build failed: hbnf" >&2; fi
	: > /o/verdicts.tsv
	while IFS="$(printf "\t")" read -r f kind what; do
		run() { label=$1; shift; want "$label" || return 0
			if "$@" "/o/cases/$f" > /o/out.txt 2> /dev/null && grep -q "^ok" /o/out.txt; then v=accept; else v=refuse; fi
			printf "%s\t%s\t%s\n" "$f" "$label" "$v" >> /o/verdicts.tsv; }
		run "expat" /o/bin-expat_c events
		run "libxml2 DOM" /o/bin-libxml2_c dom
		run "libxml2 SAX2" /o/bin-libxml2_c sax
		run "pugixml" /o/bin-pugixml_cpp
		run "TinyXML-2" /o/bin-tinyxml2_cpp
		run "RapidXML" /o/bin-rapidxml_cpp
		run "ElementTree" python3 /w/bench/formats/time_xml.py etree
		run "lxml" python3 /w/bench/formats/time_xml.py lxml
		run "fast-xml-parser" node /w/bench/libs/time_xml.js fxp
		run "sax (Node)" node /w/bench/libs/time_xml.js sax
		run "hbnf" /o/bin-hbnf
	done < /o/cases/index.tsv'

# keep the verdicts of the parsers that were not rerun, replace the rest, and keep the keys
python3 - "$W" "$res" "$stale" <<'PY'
import sys
W, res, stale = sys.argv[1], sys.argv[2], set(sys.argv[3].split("|"))
rows = [l.rstrip("\n").split("\t") for l in open(res + "/xml-conformance-verdicts.tsv") if l.strip()]
rows = [r for r in rows if r[1] not in stale] + [l.rstrip("\n").split("\t") for l in open(W + "/verdicts.tsv")]
open(res + "/xml-conformance-verdicts.tsv", "w").write("".join("\t".join(r) + "\n" for r in rows))
keys = dict(l.rstrip("\n").split("\t") for l in open(res + "/xml-conformance.keys") if "\t" in l)
for l in open(W + "/keys.new"):
    t, k = l.rstrip("\n").split("\t")
    if t in stale: keys[t] = k
open(res + "/xml-conformance.keys", "w").write("".join("%s\t%s\n" % (t, k) for t, k in keys.items()))
PY
cp "$W/cases/index.tsv" "$W/index.tsv"
python3 - "$W" "$res" > "$res/xml-conformance.md" <<'PY'
import sys, collections
W, res = sys.argv[1], sys.argv[2]
cases = [l.rstrip("\n").split("\t") for l in open(W + "/cases/index.tsv")]
v = collections.defaultdict(dict); tools = []
for l in open(res + "/xml-conformance-verdicts.tsv"):
    f, t, a = l.rstrip("\n").split("\t"); v[t][f] = a
    if t not in tools: tools.append(t)
ill = [c for c in cases if c[1] == "ill"]; wf = [c for c in cases if c[1] == "wf"]
ref = v["expat"]
print("# XML conformance of the parsers of the library benchmark\n")
print("The same %d documents through each parser, by the drivers of `bench/libs.sh` (`sh bench/xml-conformance.sh`): %d break one well-formedness constraint of XML 1.0 each and a conforming parser refuses them; %d are well-formed, so that refusing everything does not look conformant.  Expat, with its own checks on, is the reference.  The check is done once and kept: each parser's verdicts are stored with a key (its version, the case set, for hbnf the grammar) and rerun only when the key changes.\n" % (len(cases), len(ill), len(wf)))
print("| parser | refuses the ill-formed | accepts the well-formed | accepts, wrongly |")
print("|---|---:|---:|---|")
rows = sorted(tools, key=lambda t: -sum(v[t].get(c[0]) == "refuse" for c in ill))
summ = []
for t in rows:
    r = sum(v[t].get(c[0]) == "refuse" for c in ill); a = sum(v[t].get(c[0]) == "accept" for c in wf)
    summ.append("%s\t%d\t%d\t%d\t%d\n" % (t, r, len(ill), a, len(wf)))
    wrong = ", ".join(c[2] for c in ill if v[t].get(c[0]) == "accept")
    wrong = wrong if len(wrong) < 150 else "%d inputs (see below)" % (len(ill) - r)
    print("| %s | %d of %d | %d of %d | %s |" % (t, r, len(ill), a, len(wf), wrong if r < len(ill) else "none"))
open(res + "/xml-conformance.tsv", "w").write("".join(summ))
print("\n## Each input\n")
print("| input | " + " | ".join(rows) + " |")
print("|---|" + "---|" * len(rows))
for c in cases:
    cells = []
    for t in rows:
        a = v[t].get(c[0], "?"); right = (a == "refuse") == (c[1] == "ill")
        cells.append(("**%s**" % a) if not right else a)
    print("| %s%s | %s |" % (c[2], "" if c[1] == "ill" else " (well-formed)", " | ".join(cells)))
bad = [c[2] for c in cases if (ref[c[0]] == "refuse") != (c[1] == "ill")]
print("\nA word in bold is a wrong answer.  Where expat itself disagrees with what the input is meant to show: %s." % (", ".join(bad) if bad else "nowhere"))
PY
echo "xml-conformance: written"
