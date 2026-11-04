#!/bin/sh
# xml-conformance.sh -- does each XML parser of the library benchmark refuse what XML 1.0 forbids?  The same
# drivers as bench/libs.sh (bench/libs/*), the inputs of bench/formats/xml_cases.py: 34 documents that each
# break one well-formedness constraint, and 11 well-formed ones that a careless checker might refuse.  Writes
# bench/results/xml-conformance.md.  Expat, with its own checks on, is the reference; the table says where
# the inputs and expat differ.  Needs docker and the image libs.sh builds (hbnf-libs-glibc).
#   HBNF=/path/to/hbnf sh bench/xml-conformance.sh        (default ./hbnf)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
hb=${HBNF:-$root/hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; chmod 755 "$W"
python3 "$here/formats/xml_cases.py" "$W/cases"
HBNF_TEMPLATES="$root/templates" "$hb" "$root/corpus/xml/xml.hbnf" --backend=c > "$W/xml.c"
docker build -q -t hbnf-libs-glibc -f "$here/libs/Dockerfile.glibc" "$here/libs" > /dev/null
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/w:ro" -v "$W:/o" hbnf-libs-glibc sh -c '
	set -u; cd /o; L=/w/bench/libs; CC="gcc -O2 -w"; CXX="g++ -O2 -w -std=c++20"
	build() { src=$1; shift; exe=/o/bin-$(basename "$src" | tr . _); case $src in *.cpp) c="$CXX" ;; *) c="$CC" ;; esac
		$c -I"$L" "$L/$src" -o "$exe" "$@" 2> /dev/null || echo "build failed: $src" >&2; }
	build expat.c -lexpat; build libxml2.c $(pkg-config --cflags --libs libxml-2.0); build pugixml.cpp -lpugixml
	build tinyxml2.cpp -ltinyxml2; build rapidxml.cpp
	t=$(sed -n "s/^bool parse_text(const char \*text, \(.*\) \*out,\$/\1/p" /o/xml.c)
	cat /o/xml.c /w/corpus/c/check.c > /o/xml-m.c; $CC -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$t" /o/xml-m.c -o /o/bin-hbnf 2> /dev/null || echo "build failed: hbnf" >&2
	: > /o/verdicts.tsv
	while IFS="$(printf "\t")" read -r f kind what; do
		run() { label=$1; shift; if "$@" "/o/cases/$f" > /o/out.txt 2> /dev/null && grep -q "^ok" /o/out.txt; then v=accept; else v=refuse; fi
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
python3 - "$W" > "$here/results/xml-conformance.md" <<'PY'
import sys, collections
W = sys.argv[1]
cases = [l.rstrip("\n").split("\t") for l in open(W + "/cases/index.tsv")]
v = collections.defaultdict(dict)
tools = []
for l in open(W + "/verdicts.tsv"):
    f, t, a = l.rstrip("\n").split("\t")
    v[t][f] = a
    if t not in tools: tools.append(t)
ill = [c for c in cases if c[1] == "ill"]; wf = [c for c in cases if c[1] == "wf"]
ref = v["expat"]
print("# XML conformance of the parsers of the library benchmark\n")
print("The same %d documents through each parser, by the drivers of `bench/libs.sh` (`sh bench/xml-conformance.sh`): %d break one well-formedness constraint of XML 1.0 each and a conforming parser refuses them; %d are well-formed, so that refusing everything does not look conformant.  Expat, with its own checks on, is the reference.\n" % (len(cases), len(ill), len(wf)))
print("| parser | refuses the ill-formed | accepts the well-formed | accepts, wrongly |")
print("|---|---:|---:|---|")
rows = sorted(tools, key=lambda t: -sum(v[t][c[0]] == "refuse" for c in ill))
for t in rows:
    r = sum(v[t][c[0]] == "refuse" for c in ill); a = sum(v[t][c[0]] == "accept" for c in wf)
    wrong = ", ".join(c[2] for c in ill if v[t][c[0]] == "accept")
    wrong = wrong if len(wrong) < 150 else "%d inputs (see below)" % (len(ill) - r)
    print("| %s | %d of %d | %d of %d | %s |" % (t, r, len(ill), a, len(wf), wrong if r < len(ill) else "none"))
with open(W + "/summary.tsv", "w") as sm:
    for t in rows:
        sm.write("%s\t%d\t%d\t%d\t%d\n" % (t, sum(v[t][c[0]] == "refuse" for c in ill), len(ill), sum(v[t][c[0]] == "accept" for c in wf), len(wf)))
print("\n## Each input\n")
print("| input | " + " | ".join(rows) + " |")
print("|---|" + "---|" * len(rows))
for c in cases:
    cells = []
    for t in rows:
        a = v[t][c[0]]; right = (a == "refuse") == (c[1] == "ill")
        cells.append(("**%s**" % a) if not right else a)
    print("| %s%s | %s |" % (c[2], "" if c[1] == "ill" else " (well-formed)", " | ".join(cells)))
bad = [c[2] for c in cases if (ref[c[0]] == "refuse") != (c[1] == "ill")]
print("\nA word in bold is a wrong answer.  Where expat itself disagrees with what the input is meant to show: %s." % (", ".join(bad) if bad else "nowhere"))
PY
cp "$W/summary.tsv" "$here/results/xml-conformance.tsv"
echo written; head -22 "$here/results/xml-conformance.md" | cut -c1-200
