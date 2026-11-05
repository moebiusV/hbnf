**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 1.7 ms | 1170 MB/s | 5 MB | 1.8x |
| simdjson (DOM) | 1.9 ms | 1075 MB/s | 14 MB | 6.7x |
| hbnf (C backend), typed tree | 1.9 ms | 1053 MB/s | 7 MB | 2.9x |
| RapidJSON | 4.8 ms | 412 MB/s | 9 MB | 3.8x |
| Node JSON.parse | 9.3 ms | 216 MB/s | 55 MB | 27.9x |
| Python json | 11 ms | 177 MB/s | 20 MB | 9.7x |
| cJSON | 11 ms | 177 MB/s | 17 MB | 8.1x |
| serde_json (Rust) 1.0.154 | 13 ms | 151 MB/s | 20 MB | 9.9x |
| Jansson | 28 ms | 73 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 4.0 ms | 497 MB/s | 11 MB | 5.0x |
| hbnf (C backend), %emit tape | 4.4 ms | 454 MB/s | 7 MB | 2.8x |
| tomlc17 | 36 ms | 55 MB/s | 17 MB | 8.3x |
| toml++ | 43 ms | 46 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 49 ms | 41 MB/s | 58 MB | 29.6x |
| Python tomllib | 241 ms | 8 MB/s | 26 MB | 13.0x |
| toml11 | 618 ms | 3 MB/s | 94 MB | 48.8x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 6.8 ms | 293 MB/s | 5 MB | 1.8x |
| hbnf (C backend), typed tree | 8.5 ms | 235 MB/s | 19 MB | 9.3x |
| rapidyaml | 15 ms | 134 MB/s | 27 MB | 13.3x |
| libyaml | 36 ms | 55 MB/s | 40 MB | 20.4x |
| libfyaml | 65 ms | 31 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 119 ms | 17 MB/s | 81 MB | 41.9x |
| yaml-cpp | 254 ms | 8 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 697 ms | 3 MB/s | 117 MB | 61.1x |

**XML 1.0** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | builds | parse time | MB/s | peak RSS | RSS over the input | conforms to XML 1.0 (refuses the 34 ill-formed documents) |
|---|---|---:|---:|---:|---:|---:|
| pugixml | DOM, in place | 2.9 ms | 683 MB/s | 10 MB | 4.5x | ❌ 8 of 34 |
| hbnf (C backend), tape | a flat tape of 64-bit words | 3.7 ms | 545 MB/s | 5 MB | 2.1x | 34 of 34 |
| RapidXML | DOM, in place | 3.8 ms | 525 MB/s | 13 MB | 5.9x | ❌ 7 of 34 |
| hbnf (C backend), tree | the grammar's typed tree | 5.0 ms | 400 MB/s | 10 MB | 4.4x | 34 of 34 |
| libxml2, SAX2 events only | nothing (handlers count) | 5.3 ms | 375 MB/s | 6 MB | 2.5x | 34 of 34 |
| expat, events only | nothing (handlers count) | 8.7 ms | 229 MB/s | 5 MB | 1.8x | 34 of 34 |
| Python xml.parsers.expat, no handlers | nothing (well-formedness only) | 9.7 ms | 207 MB/s | 12 MB | 5.8x | 34 of 34 |
| TinyXML-2 | DOM | 11 ms | 183 MB/s | 17 MB | 8.1x | ❌ 9 of 34 |
| expat, events copied into a tree | a cheap tree of copies | 12 ms | 161 MB/s | 11 MB | 5.1x | 34 of 34 |
| libxml2, DOM | DOM | 19 ms | 106 MB/s | 29 MB | 14.5x | 34 of 34 |
| lxml (Python) | Element tree on libxml2 | 26 ms | 76 MB/s | 41 MB | 20.9x | 34 of 34 |
| Python xml.etree.ElementTree | Element tree | 32 ms | 63 MB/s | 30 MB | 15.1x | 34 of 34 |
| Python xml.parsers.expat, Python callbacks | nothing (Python callbacks count) | 32 ms | 62 MB/s | 13 MB | 5.8x | 34 of 34 |
| sax (Node) | nothing (handlers count) | 110 ms | 18 MB/s | 70 MB | 35.8x | ❌ 20 of 34 |
| fast-xml-parser (Node) | JavaScript objects | 282 ms | 7 MB/s | 113 MB | 58.3x | ❌ 0 of 34 |

_2026-11-04; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf acadd88.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree.  The XML parsers: expat 2.9.0, libxml2 2.12.7, pugixml 1.14, TinyXML-2 11.0.0, RapidXML 1.13 (Marcin Kalicinski's original, unmaintained since 2009), lxml 5.4.0, fast-xml-parser 5.11.2, sax 1.6.1; the first six are Debian packages, the Node ones are locked by `bench/libs/node/package-lock.json`.  Every XML parser reads the same catalog and must find the same number of elements, of attributes (not counting xmlns declarations) and of non-blank bytes of text, references decoded, as ElementTree does (a driver that cannot count something does not, and a mismatch is a `check failed` row).  The time is the parse call alone; the counting walks of the tree parsers come after the clock.  expat, libxml2's SAX2 and sax build nothing, their handlers count, and the expat row that copies makes a small tree of names, attributes and text.  pugixml and RapidXML parse the buffer in place, the others leave it alone.  hbnf's XML grammar is measured twice: its typed tree and the same grammar under `--layout=tape` (the tape holds the elements, attributes and texts as 64-bit words; the driver counts from it), and that tree and that tape is the grammar's concrete syntax (a reference is a node and characters are not decoded).  The last column is `bench/xml-conformance.sh` (`bench/results/xml-conformance.md`): of 34 documents that each break one well-formedness constraint of XML 1.0 (a forbidden control character, invalid UTF-8, `]]>` or `<` where they may not be, two root elements, a bad character reference, a duplicate attribute, an undeclared entity ...), how many the parser refuses; marks a parser that does not refuse all of them or refuses a well-formed one; conforming parsers are left unmarked.  Expat, libxml2, ElementTree and lxml refuse all of them (34 of 34).  **pugixml (8 of 34), TinyXML-2 (9 of 34) and RapidXML (7 of 34) are not conforming XML parsers**: they check the structure of the tags and accept most content that XML forbids, and fast-xml-parser's `parse` (0 of 34) does not check well-formedness at all (the library has a separate `XMLValidator`, which this table does not time).  hbnf's grammar refuses 27 of 34.  A parser that skips checks does less work, so the time column is not like for like for the marked rows.  The check is done once and kept: a parser is checked again only when its version, the case set or, for hbnf, its grammar or generator changes.  **The XML rows were measured again on 2026-11-05, XML only, with the grammar conforming (hbnf 9884a84), on a busy machine** (the YAML probe read 18.3-19 ms, against 8.4-9.6 when quiet; 7 runs each, cold process, core 5).  The other parsers read within 3-8% of the first such run and of their quiet readings (libxml2 SAX2 5.3 ms, expat 8.7, libxml2 DOM 19), but hbnf allocates and touches many fresh pages, which cost about three times as much under load, so its two rows are probably a little slower here than on a quiet machine; the arena sized from the input and backed ahead of use (which saves page faults when the kernel cannot back it with huge pages) did not show in this run.  Of the parsers that conform to XML 1.0, hbnf's tape is the fastest and its tree is ahead of libxml2's SAX2, which builds nothing, by a small margin that this noise could erase.  JSON, TOML and YAML are from the earlier quiet run._
