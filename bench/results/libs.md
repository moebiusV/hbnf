**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.7 ms | 1191 MB/s | 13 MB | 6.0x |
| hbnf (C backend), %emit tape | 1.8 ms | 1130 MB/s | 5 MB | 1.8x |
| hbnf (C backend), typed tree | 2.1 ms | 939 MB/s | 9 MB | 3.9x |
| RapidJSON | 5.4 ms | 373 MB/s | 9 MB | 3.8x |
| Node JSON.parse | 9.7 ms | 205 MB/s | 54 MB | 27.8x |
| cJSON | 12 ms | 168 MB/s | 17 MB | 8.1x |
| Python json | 12 ms | 163 MB/s | 20 MB | 9.8x |
| serde_json (Rust) 1.0.154 | 16 ms | 127 MB/s | 20 MB | 9.9x |
| Jansson | 29 ms | 68 MB/s | 20 MB | 9.8x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 4.8 ms | 411 MB/s | 7 MB | 2.9x |
| hbnf (C backend), typed tree | 6.7 ms | 297 MB/s | 17 MB | 8.1x |
| tomlc17 | 38 ms | 53 MB/s | 17 MB | 8.3x |
| toml++ | 46 ms | 43 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 52 ms | 38 MB/s | 58 MB | 29.7x |
| Python tomllib | 255 ms | 8 MB/s | 26 MB | 12.9x |
| toml11 | 668 ms | 3 MB/s | 93 MB | 48.4x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 7.2 ms | 277 MB/s | 5 MB | 1.9x |
| hbnf (C backend), typed tree | 12 ms | 173 MB/s | 35 MB | 17.7x |
| rapidyaml | 15 ms | 130 MB/s | 27 MB | 13.5x |
| libyaml | 38 ms | 52 MB/s | 39 MB | 19.8x |
| libfyaml | 68 ms | 29 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 124 ms | 16 MB/s | 82 MB | 42.2x |
| yaml-cpp | 272 ms | 7 MB/s | 110 MB | 57.4x |
| PyYAML on libyaml (C) | 776 ms | 3 MB/s | 118 MB | 61.1x |

_2026-10-29; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf 705ae19.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree._
