#!/usr/bin/env python3
"""time_xml.py TOOL FILE: parse FILE with a Python XML library and print
"ok BYTES MS RSS_KIB ELEMENTS ATTRIBUTES TEXT" (see bench/libs/timer.h).  TOOL:
  etree        xml.etree.ElementTree.fromstring (its C accelerator on pyexpat), a tree of Elements
  lxml         lxml.etree.fromstring (libxml2), a tree of elements
  pyexpat      xml.parsers.expat with no handler set: the raw expat, which reads the document and reports nothing
  pyexpat-cb   xml.parsers.expat with Python start, end and text handlers that count elements and attributes
The file is read first (as bytes) and the clock is around the parse; the walk that counts comes after."""
import re
import resource
import sys
import time

tool, path = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
nb = re.compile(rb"[ \t\r\n]")
el = at = tx = 0
res = None
t0 = time.perf_counter()
if tool == "etree":
    import xml.etree.ElementTree as ET
    res = ET.fromstring(data)
elif tool == "lxml":
    import lxml.etree as ET
    res = ET.fromstring(data)
elif tool in ("pyexpat", "pyexpat-cb"):
    import xml.parsers.expat as expat
    p = expat.ParserCreate()
    if tool == "pyexpat-cb":
        def start(name, attrs):
            global el, at
            el += 1
            at += sum(1 for k in attrs if not k.startswith("xmlns"))
        p.StartElementHandler = start
        p.EndElementHandler = lambda name: None
        p.CharacterDataHandler = lambda s: None
    p.Parse(data, True)
else:
    sys.exit(2)
ms = (time.perf_counter() - t0) * 1000.0
rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
if res is not None:
    for e in res.iter():
        if not isinstance(e.tag, str):   # lxml: comments and processing instructions
            if e.tail:
                tx += len(nb.sub(b"", e.tail.encode("utf-8")))
            continue
        el += 1
        at += len(e.attrib)
        for t in (e.text, e.tail):
            if t:
                tx += len(nb.sub(b"", t.encode("utf-8")))
else:
    tx = -1
if tool == "pyexpat":
    el = at = -1
print("ok %d %.2f %d %d %d %d" % (len(data), ms, rss, el, at, tx))
