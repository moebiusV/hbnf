#!/usr/bin/env python3
"""xml_expect.py FILE: what every XML parser of bench/libs.sh must find in FILE, as ElementTree reads it:
"ELEMENTS ATTRIBUTES TEXT" (attributes without the xmlns declarations; TEXT the bytes of character data, entity
and character references decoded and CDATA included, that are not blanks)."""
import re
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
el = at = tx = 0
for e in root.iter():
    el += 1
    at += len(e.attrib)
    for t in (e.text, e.tail):
        if t:
            tx += len(re.sub(r"[ \t\r\n]", "", t).encode("utf-8"))
print(el, at, tx)
