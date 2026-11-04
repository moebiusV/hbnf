**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.7 ms | 1184 MB/s | 14 MB | 6.4x |
| hbnf (C backend), %emit tape | 1.8 ms | 1130 MB/s | 5 MB | 1.8x |
| hbnf (C backend), typed tree | 1.9 ms | 1036 MB/s | 7 MB | 2.8x |
| RapidJSON | 5.1 ms | 390 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 9.5 ms | 211 MB/s | 54 MB | 27.8x |
| cJSON | 11 ms | 181 MB/s | 17 MB | 8.1x |
| Python json | 11 ms | 179 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 14 ms | 148 MB/s | 20 MB | 9.8x |
| Jansson | 28 ms | 72 MB/s | 20 MB | 9.8x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 4.6 ms | 437 MB/s | 7 MB | 2.9x |
| hbnf (C backend), typed tree | 5.1 ms | 394 MB/s | 11 MB | 5.0x |
| tomlc17 | 38 ms | 53 MB/s | 17 MB | 8.3x |
| toml++ | 45 ms | 44 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 57 ms | 35 MB/s | 57 MB | 29.4x |
| Python tomllib | 245 ms | 8 MB/s | 26 MB | 12.9x |
| toml11 | 646 ms | 3 MB/s | 93 MB | 48.5x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 6.9 ms | 287 MB/s | 5 MB | 1.9x |
| hbnf (C backend), typed tree | 18 ms | 108 MB/s | 28 MB | 13.9x |
| rapidyaml | 22 ms | 92 MB/s | 25 MB | 12.6x |
| libyaml | 41 ms | 49 MB/s | 39 MB | 19.8x |
| libfyaml | 66 ms | 30 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 116 ms | 17 MB/s | 80 MB | 41.4x |
| yaml-cpp | 276 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 687 ms | 3 MB/s | 117 MB | 61.0x |

**XML 1.0** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | builds | parse time | MB/s | peak RSS | RSS over the input |
|---|---|---:|---:|---:|---:|
| pugixml | DOM, in place | 3.0 ms | 673 MB/s | 10 MB | 4.5x |
| RapidXML | DOM, in place | 4.1 ms | 491 MB/s | 13 MB | 5.9x |
| libxml2, SAX2 events only | nothing (handlers count) | 5.0 ms | 403 MB/s | 6 MB | 2.5x |
| hbnf (C backend), tree | the grammar's typed tree | 8.5 ms | 235 MB/s | 13 MB | 6.3x |
| expat, events only | nothing (handlers count) | 8.7 ms | 229 MB/s | 5 MB | 1.9x |
| Python xml.parsers.expat, no handlers | nothing (well-formedness only) | 9.3 ms | 214 MB/s | 13 MB | 5.9x |
| TinyXML-2 | DOM | 11 ms | 181 MB/s | 17 MB | 8.1x |
| expat, events copied into a tree | a cheap tree of copies | 13 ms | 159 MB/s | 11 MB | 5.1x |
| libxml2, DOM | DOM | 19 ms | 108 MB/s | 29 MB | 14.5x |
| lxml (Python) | Element tree on libxml2 | 25 ms | 79 MB/s | 42 MB | 21.1x |
| Python xml.etree.ElementTree | Element tree | 32 ms | 63 MB/s | 30 MB | 14.9x |
| Python xml.parsers.expat, Python callbacks | nothing (Python callbacks count) | 32 ms | 63 MB/s | 12 MB | 5.8x |
| sax (Node) | nothing (handlers count) | 113 ms | 18 MB/s | 69 MB | 35.6x |
| fast-xml-parser (Node) | JavaScript objects | 284 ms | 7 MB/s | 113 MB | 58.7x |

_2026-11-03; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf dafb450.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree.  The XML parsers: expat 2.9.0, libxml2 2.12.7, pugixml 1.14, TinyXML-2 11.0.0, RapidXML 1.13 (Marcin Kalicinski's original, unmaintained since 2009), lxml 5.4.0, fast-xml-parser 5.11.2, sax 1.6.1; the first six are Debian packages, the Node ones are locked by `bench/libs/node/package-lock.json`.  Every XML parser reads the same catalog and must find the same number of elements, of attributes (not counting xmlns declarations) and of non-blank bytes of text, references decoded, as ElementTree does (a driver that cannot count something does not, and a mismatch is a `check failed` row).  The time is the parse call alone; the counting walks of the tree parsers come after the clock.  expat, libxml2's SAX2 and sax build nothing, their handlers count, and the expat row that copies makes a small tree of names, attributes and text.  pugixml and RapidXML parse the buffer in place, the others leave it alone.  hbnf's XML grammar has no `%emit tape` row: `corpus/xml/xml.hbnf` does not generate under `--layout=tape` yet, so only its typed tree is measured, and that tree is the grammar's concrete syntax (a reference is a node and characters are not decoded)._
