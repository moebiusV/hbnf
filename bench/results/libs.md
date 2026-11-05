**JSON** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 2.2 ms | 922 MB/s | 4 MB | 1.6x |
| simdjson (DOM) | 2.3 ms | 870 MB/s | 12 MB | 5.6x |
| hbnf (C backend), typed tree | 2.8 ms | 727 MB/s | 7 MB | 2.7x |
| RapidJSON | 5.1 ms | 393 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 9.6 ms | 207 MB/s | 54 MB | 27.7x |
| Python json | 12 ms | 170 MB/s | 20 MB | 9.7x |
| cJSON | 12 ms | 166 MB/s | 17 MB | 8.1x |
| serde_json (Rust) 1.0.154 | 14 ms | 145 MB/s | 20 MB | 9.8x |
| Jansson | 29 ms | 69 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 5.1 ms | 391 MB/s | 5 MB | 2.0x |
| hbnf (C backend), typed tree | 5.8 ms | 345 MB/s | 10 MB | 4.3x |
| tomlc17 | 38 ms | 52 MB/s | 17 MB | 8.3x |
| toml++ | 45 ms | 44 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 59 ms | 34 MB/s | 57 MB | 29.4x |
| Python tomllib | 255 ms | 8 MB/s | 26 MB | 12.8x |
| toml11 | 650 ms | 3 MB/s | 93 MB | 48.5x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 7.5 ms | 264 MB/s | 5 MB | 1.7x |
| hbnf (C backend), typed tree | 12 ms | 160 MB/s | 18 MB | 8.9x |
| rapidyaml | 21 ms | 93 MB/s | 25 MB | 12.4x |
| libyaml | 42 ms | 48 MB/s | 39 MB | 19.8x |
| libfyaml | 69 ms | 29 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 123 ms | 16 MB/s | 81 MB | 41.8x |
| yaml-cpp | 287 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 709 ms | 3 MB/s | 118 MB | 61.1x |

**XML 1.0** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | builds | parse time | MB/s | peak RSS | RSS over the input | conforms to XML 1.0 (refuses the 34 ill-formed documents) |
|---|---|---:|---:|---:|---:|---:|
| pugixml | DOM, in place | 2.8 ms | 719 MB/s | 10 MB | 4.6x | ❌ 8 of 34 |
| hbnf (C backend), tape | a flat tape of 64-bit words | 3.5 ms | 564 MB/s | 5 MB | 2.1x | 34 of 34 |
| RapidXML | DOM, in place | 3.9 ms | 515 MB/s | 13 MB | 5.9x | ❌ 7 of 34 |
| hbnf (C backend), tree | the grammar's typed tree | 4.3 ms | 462 MB/s | 10 MB | 4.5x | 34 of 34 |
| libxml2, SAX2 events only | nothing (handlers count) | 4.8 ms | 415 MB/s | 6 MB | 2.4x | 34 of 34 |
| expat, events only | nothing (handlers count) | 8.4 ms | 238 MB/s | 5 MB | 1.8x | 34 of 34 |
| Python xml.parsers.expat, no handlers | nothing (well-formedness only) | 9.1 ms | 219 MB/s | 12 MB | 5.7x | 34 of 34 |
| TinyXML-2 | DOM | 10 ms | 196 MB/s | 17 MB | 8.1x | ❌ 9 of 34 |
| expat, events copied into a tree | a cheap tree of copies | 12 ms | 163 MB/s | 11 MB | 5.1x | 34 of 34 |
| libxml2, DOM | DOM | 17 ms | 115 MB/s | 29 MB | 14.6x | 34 of 34 |
| lxml (Python) | Element tree on libxml2 | 25 ms | 81 MB/s | 42 MB | 21.1x | 34 of 34 |
| Python xml.etree.ElementTree | Element tree | 31 ms | 65 MB/s | 30 MB | 14.9x | 34 of 34 |
| Python xml.parsers.expat, Python callbacks | nothing (Python callbacks count) | 32 ms | 63 MB/s | 13 MB | 5.8x | 34 of 34 |
| sax (Node) | nothing (handlers count) | 114 ms | 18 MB/s | 69 MB | 35.5x | ❌ 20 of 34 |
| fast-xml-parser (Node) | JavaScript objects | 271 ms | 7 MB/s | 113 MB | 58.4x | ❌ 0 of 34 |

_2026-11-05; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf f95d41d.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree.  The XML parsers: expat 2.9.0, libxml2 2.12.7, pugixml 1.14, TinyXML-2 11.0.0, RapidXML 1.13 (Marcin Kalicinski's original, unmaintained since 2009), lxml 5.4.0, fast-xml-parser 5.11.2, sax 1.6.1; the first six are Debian packages, the Node ones are locked by `bench/libs/node/package-lock.json`.  Every XML parser reads the same catalog and must find the same number of elements, of attributes (not counting xmlns declarations) and of non-blank bytes of text, references decoded, as ElementTree does (a driver that cannot count something does not, and a mismatch is a `check failed` row).  The time is the parse call alone; the counting walks of the tree parsers come after the clock.  expat, libxml2's SAX2 and sax build nothing, their handlers count, and the expat row that copies makes a small tree of names, attributes and text.  pugixml and RapidXML parse the buffer in place, the others leave it alone.  hbnf's XML grammar is measured twice: its typed tree and the same grammar under `--layout=tape` (the tape holds the elements, attributes and texts as 64-bit words; the driver counts from it), and that tree and that tape is the grammar's concrete syntax (a reference is a node and characters are not decoded).  The last column is `bench/xml-conformance.sh` (`bench/results/xml-conformance.md`): of 34 documents that each break one well-formedness constraint of XML 1.0 (a forbidden control character, invalid UTF-8, `]]>` or `<` where they may not be, two root elements, a bad character reference, a duplicate attribute, an undeclared entity ...), how many the parser refuses; ❌ marks a parser that does not refuse all of them or refuses a well-formed one; conforming parsers are left unmarked.  Expat, libxml2, ElementTree and lxml refuse all of them (34 of 34).  **pugixml (8 of 34), TinyXML-2 (9 of 34) and RapidXML (7 of 34) are not conforming XML parsers**: they check the structure of the tags and accept most content that XML forbids, and fast-xml-parser's `parse` (0 of 34) does not check well-formedness at all (the library has a separate `XMLValidator`, which this table does not time).  hbnf's grammar refuses 34 of 34.  A parser that skips checks does less work, so the time column is not like for like for the marked rows.  The check is done once and kept: a parser is checked again only when its version, the case set or, for hbnf, its grammar or generator changes.  **Measured on a busy machine, as quiet as it would get** (`fuzzy_search` on cores 0-4 and a VM; the YAML probe read 18.0-19.2 ms before and after, against 8.4-9.6 when quiet; load average 9; best of 9 runs each in place of 5, to catch the quieter moments; one core).  The reference rows say how much it cost: RapidJSON 5.1 ms (5.0 quiet), tomlc17 38 (36-38) and libyaml 42 (37-41) are at their quiet readings, simdjson 2.3 (1.7) and rapidyaml 21 (15-18) are 20-35% high, and the XML parsers other than hbnf reproduce their quiet readings (libxml2 SAX2 4.8 ms, expat 8.4).  hbnf's own rows are the ones the load hurts most, because it allocates and touches many fresh pages and a page fault costs about three times as much under this load (its JSON tree read 1.9 ms and its YAML tree 8.5 on the last quiet run, its XML tree 3.4 before the grammar was made conforming): read them as upper bounds.  No figure has been adjusted.  A quiet rerun is in TODO.md._
