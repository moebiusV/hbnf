**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 1.7 ms | 1150 MB/s | 5 MB | 1.8x |
| simdjson (DOM) | 1.7 ms | 1150 MB/s | 14 MB | 6.6x |
| hbnf (C backend), typed tree | 1.9 ms | 1053 MB/s | 7 MB | 2.9x |
| RapidJSON | 5.0 ms | 400 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 9.7 ms | 206 MB/s | 55 MB | 27.9x |
| cJSON | 11 ms | 180 MB/s | 17 MB | 8.1x |
| Python json | 12 ms | 170 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 14 ms | 143 MB/s | 20 MB | 9.8x |
| Jansson | 28 ms | 73 MB/s | 20 MB | 9.8x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 4.1 ms | 488 MB/s | 7 MB | 2.9x |
| hbnf (C backend), typed tree | 4.2 ms | 471 MB/s | 11 MB | 5.0x |
| tomlc17 | 38 ms | 53 MB/s | 17 MB | 8.4x |
| toml++ | 43 ms | 47 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 51 ms | 39 MB/s | 58 MB | 29.8x |
| Python tomllib | 248 ms | 8 MB/s | 26 MB | 12.9x |
| toml11 | 640 ms | 3 MB/s | 95 MB | 49.1x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 6.9 ms | 289 MB/s | 5 MB | 1.9x |
| hbnf (C backend), typed tree | 8.5 ms | 234 MB/s | 29 MB | 14.5x |
| rapidyaml | 16 ms | 128 MB/s | 26 MB | 13.0x |
| libyaml | 38 ms | 53 MB/s | 39 MB | 19.9x |
| libfyaml | 68 ms | 29 MB/s | 84 MB | 43.7x |
| js-yaml (Node) | 121 ms | 16 MB/s | 81 MB | 41.8x |
| yaml-cpp | 268 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 709 ms | 3 MB/s | 118 MB | 61.1x |

**XML 1.0** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | builds | parse time | MB/s | peak RSS | RSS over the input |
|---|---|---:|---:|---:|---:|
| pugixml | DOM, in place | 2.9 ms | 696 MB/s | 10 MB | 4.7x |
| RapidXML | DOM, in place | 3.6 ms | 549 MB/s | 13 MB | 5.9x |
| libxml2, SAX2 events only | nothing (handlers count) | 5.3 ms | 376 MB/s | 6 MB | 2.5x |
| hbnf (C backend), tree | the grammar's typed tree | 7.3 ms | 273 MB/s | 15 MB | 7.2x |
| expat, events only | nothing (handlers count) | 8.9 ms | 223 MB/s | 5 MB | 1.8x |
| Python xml.parsers.expat, no handlers | nothing (well-formedness only) | 9.4 ms | 212 MB/s | 12 MB | 5.8x |
| TinyXML-2 | DOM | 11 ms | 181 MB/s | 17 MB | 8.1x |
| expat, events copied into a tree | a cheap tree of copies | 12 ms | 160 MB/s | 11 MB | 5.0x |
| libxml2, DOM | DOM | 19 ms | 108 MB/s | 29 MB | 14.5x |
| lxml (Python) | Element tree on libxml2 | 26 ms | 78 MB/s | 42 MB | 21.1x |
| Python xml.etree.ElementTree | Element tree | 32 ms | 63 MB/s | 30 MB | 15.0x |
| Python xml.parsers.expat, Python callbacks | nothing (Python callbacks count) | 32 ms | 62 MB/s | 13 MB | 5.9x |
| sax (Node) | nothing (handlers count) | 112 ms | 18 MB/s | 69 MB | 35.6x |
| fast-xml-parser (Node) | JavaScript objects | 280 ms | 7 MB/s | 114 MB | 59.2x |

_2026-11-03; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf e8ecf39.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree.  The XML parsers: expat 2.9.0, libxml2 2.12.7, pugixml 1.14, TinyXML-2 11.0.0, RapidXML 1.13 (Marcin Kalicinski's original, unmaintained since 2009), lxml 5.4.0, fast-xml-parser 5.11.2, sax 1.6.1; the first six are Debian packages, the Node ones are locked by `bench/libs/node/package-lock.json`.  Every XML parser reads the same catalog and must find the same number of elements, of attributes (not counting xmlns declarations) and of non-blank bytes of text, references decoded, as ElementTree does (a driver that cannot count something does not, and a mismatch is a `check failed` row).  The time is the parse call alone; the counting walks of the tree parsers come after the clock.  expat, libxml2's SAX2 and sax build nothing, their handlers count, and the expat row that copies makes a small tree of names, attributes and text.  pugixml and RapidXML parse the buffer in place, the others leave it alone.  hbnf's XML grammar has no `%emit tape` row: `corpus/xml/xml.hbnf` does not generate under `--layout=tape` yet, so only its typed tree is measured, and that tree is the grammar's concrete syntax (a reference is a node and characters are not decoded)._
