#!/usr/bin/env python3
"""table.py WORKDIR ROOT CARGO.LOCK RUNS: the markdown of bench/results/libs.md, from the rows
inner.sh printed (FORMAT, TOOL, MS, RSS_KIB, STATUS) and the versions libs.sh recorded."""
import datetime
import re
import subprocess
import sys

W, root, lock, runs = sys.argv[1:5]
rows = {}
for line in open(f"{W}/glibc.tsv"):
    fmt, label, ms, rss, status = line.rstrip("\n").split("\t")
    rows.setdefault(fmt, []).append((label, float(ms), int(rss), status))
vers = dict(re.findall(r'name = "([^"]+)"\nversion = "([^"]+)"', open(lock).read()))
ver = open(f"{W}/glibc.ver").read().split("\n")
titles = {"json": "JSON", "toml": "TOML 1.0", "yaml": "YAML 1.2", "xml": "XML 1.0"}
# the XML table says what each parser hands the program, since they are not doing the same work
builds = {
    "hbnf (C backend), tree": "the grammar's typed tree",
    "hbnf (C backend), tape": "a flat tape of 64-bit words",
    "expat, events only": "nothing (handlers count)",
    "expat, events copied into a tree": "a cheap tree of copies",
    "libxml2, DOM": "DOM",
    "libxml2, SAX2 events only": "nothing (handlers count)",
    "pugixml": "DOM, in place",
    "TinyXML-2": "DOM",
    "RapidXML": "DOM, in place",
    "Python xml.etree.ElementTree": "Element tree",
    "lxml (Python)": "Element tree on libxml2",
    "Python xml.parsers.expat, no handlers": "nothing (well-formedness only)",
    "Python xml.parsers.expat, Python callbacks": "nothing (Python callbacks count)",
    "fast-xml-parser (Node)": "JavaScript objects",
    "sax (Node)": "nothing (handlers count)",
}
dpkg = dict(l.split("=", 1) for l in ver[5:] if "=" in l)
# bench/xml-conformance.sh: how many of the documents that break a well-formedness constraint of XML 1.0 each parser refuses
conf = {}
conforms = {}   # refuses every ill-formed document and accepts every well-formed one
try:
    for l in open(f"{root}/bench/results/xml-conformance.tsv"):
        n, r, ill, a, wf = l.rstrip("\n").split("\t")
        conf[n] = f"{r} of {ill}"
        conforms[n] = (int(r) == int(ill) and int(a) == int(wf))
except OSError:
    pass
conf_of = {
    "hbnf (C backend), tree": "hbnf", "hbnf (C backend), tape": "hbnf", "expat, events only": "expat",
    "expat, events copied into a tree": "expat", "Python xml.parsers.expat, no handlers": "expat",
    "Python xml.parsers.expat, Python callbacks": "expat", "libxml2, DOM": "libxml2 DOM",
    "libxml2, SAX2 events only": "libxml2 SAX2", "pugixml": "pugixml", "TinyXML-2": "TinyXML-2", "RapidXML": "RapidXML",
    "Python xml.etree.ElementTree": "ElementTree", "lxml (Python)": "lxml", "fast-xml-parser (Node)": "fast-xml-parser",
    "sax (Node)": "sax (Node)",
}


def tm(ms):
    if ms < 10:
        return "%.1f ms" % ms
    return "%.0f ms" % ms if ms < 1000 else "%.2f s" % (ms / 1000)


def conformance_cell(label):
    """The count; a conforming parser (refuses every ill-formed document, accepts every well-formed one) is left unmarked, the rest get a red cross."""
    k = conf_of.get(label, "")
    if k not in conf:
        return ""
    return conf[k] if conforms.get(k) else "\u274c " + conf[k]


def table(fmt, title, intro, rs):
    size = len(open(f"{W}/doc.{fmt}", "rb").read())
    print(f"**{title}** ({size / 1e6:.2f} MB, the same file for every tool; best of up to {runs} runs{intro}):\n")
    if fmt == "xml":
        print("| tool | builds | parse time | MB/s | peak RSS | RSS over the input | conforms to XML 1.0 (refuses the 34 ill-formed documents) |")
        print("|---|---|---:|---:|---:|---:|---:|")
    else:
        print("| tool | parse time | MB/s | peak RSS | RSS over the input |")
        print("|---|---:|---:|---:|---:|")
    for label, ms, rss, status in sorted(rs, key=lambda r: (r[3] != "ok", r[1])):
        if label.startswith("serde_json"):
            label += " " + vers.get("serde_json", "")
        if label.startswith("toml (Rust)"):
            label += " " + vers.get("toml", "")
        what = f" {builds.get(label, '')} |" if fmt == "xml" else ""
        cf = f" {conformance_cell(label)} |" if fmt == "xml" else ""
        if status != "ok":
            print(f"| {label} |{what} {status} | | | |{' |' if fmt == 'xml' else ''}")
            continue
        over = max(rss * 1024 - size, 0) / size
        print(f"| {label} |{what} {tm(ms)} | {size / 1e6 / (ms / 1000):.0f} MB/s | {rss // 1024} MB | {over:.1f}x |{cf}")
    print()


for fmt in ("json", "toml", "yaml", "xml"):
    table(fmt, titles[fmt], "", rows[fmt])


def xml_note():
    def d(k):
        return re.split(r"[-+~]", dpkg.get(k, "?"))[0]
    return (f"  The XML parsers: expat {d('libexpat1-dev')}, libxml2 {d('libxml2-dev')}, pugixml {d('libpugixml-dev')}, "
            f"TinyXML-2 {d('libtinyxml2-dev')}, RapidXML {d('librapidxml-dev')} (Marcin Kalicinski's original, unmaintained since 2009), "
            f"lxml {d('python3-lxml')}, fast-xml-parser {dpkg.get('fast-xml-parser', '?')}, sax {dpkg.get('sax', '?')}; the first six are Debian packages, "
            "the Node ones are locked by `bench/libs/node/package-lock.json`.  Every XML parser reads the same catalog and must find "
            "the same number of elements, of attributes (not counting xmlns declarations) and of non-blank bytes of text, references decoded, "
            "as ElementTree does (a driver that cannot count something does not, and a mismatch is a `check failed` row).  "
            "The time is the parse call alone; the counting walks of the tree parsers come after the clock.  expat, libxml2's SAX2 and sax "
            "build nothing, their handlers count, and the expat row that copies makes a small tree of names, attributes and text.  "
            "pugixml and RapidXML parse the buffer in place, the others leave it alone.  hbnf's XML grammar is measured twice: its typed tree and the same grammar under `--layout=tape` (the tape holds the "
            "elements, attributes and texts as 64-bit words; the driver counts from it), and that tree and that tape is the grammar's concrete syntax (a reference is a node and characters are not decoded)."
            + conformance_note())


def conformance_note():
    """The last column, and what it says about the parsers that do less than the standard asks."""
    if not conf:
        return ""
    c = lambda k: conf.get(k, "?")
    return ("  The last column is `bench/xml-conformance.sh` (`bench/results/xml-conformance.md`): of 34 documents that each break one "
            "well-formedness constraint of XML 1.0 (a forbidden control character, invalid UTF-8, `]]>` or `<` where they may not be, two root "
            "elements, a bad character reference, a duplicate attribute, an undeclared entity ...), how many the parser refuses; \u274c marks a parser "
            "that does not refuse all of them or refuses a well-formed one; conforming parsers are left unmarked.  "
            f"Expat, libxml2, ElementTree and lxml refuse all of them ({c('expat')}).  **pugixml ({c('pugixml')}), TinyXML-2 ({c('TinyXML-2')}) and RapidXML "
            f"({c('RapidXML')}) are not conforming XML parsers**: they check the structure of the tags and accept most content that XML forbids, "
            f"and fast-xml-parser's `parse` ({c('fast-xml-parser')}) does not check well-formedness at all (the library has a separate `XMLValidator`, "
            f"which this table does not time).  hbnf's grammar refuses {c('hbnf')}.  A parser that skips checks does less work, so the time column is not like for like "
            "for the marked rows.  The check is done once and kept: a parser is checked again only when its version, the case set or, for hbnf, its grammar or generator changes.")


rev = subprocess.check_output(["git", "-C", root, "rev-parse", "--short", "HEAD"]).decode().strip()
print(f"_{datetime.date.today()}; glibc {ver[1].split()[-1]}, {ver[0].strip()}, node {ver[2].strip().lstrip('v')}, "
      f"{ver[3].strip()}; `-O2`, the same sources and flags for every native library; hbnf {rev}.  "
      "simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build "
      "their own value types, and hbnf builds the typed tree its grammar describes, except in the row "
      "that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree." + xml_note() + "_")
