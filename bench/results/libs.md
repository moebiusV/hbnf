**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.7 ms | 1170 MB/s | 15 MB | 7.2x |
| hbnf (C backend), %emit tape | 1.8 ms | 1093 MB/s | 5 MB | 1.8x |
| hbnf (C backend), typed tree | 2.1 ms | 930 MB/s | 9 MB | 3.9x |
| RapidJSON | 5.4 ms | 368 MB/s | 9 MB | 3.8x |
| Node JSON.parse | 9.9 ms | 202 MB/s | 54 MB | 27.6x |
| cJSON | 12 ms | 166 MB/s | 17 MB | 8.1x |
| Python json | 13 ms | 160 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 15 ms | 131 MB/s | 20 MB | 9.8x |
| Jansson | 29 ms | 68 MB/s | 20 MB | 9.8x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 6.4 ms | 309 MB/s | 17 MB | 8.2x |
| tomlc17 | 39 ms | 51 MB/s | 17 MB | 8.3x |
| toml++ | 46 ms | 43 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 65 ms | 30 MB/s | 57 MB | 29.4x |
| Python tomllib | 255 ms | 8 MB/s | 26 MB | 13.0x |
| toml11 | 663 ms | 3 MB/s | 94 MB | 48.9x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 14 ms | 138 MB/s | 39 MB | 19.8x |
| rapidyaml | 16 ms | 127 MB/s | 27 MB | 13.4x |
| libyaml | 39 ms | 51 MB/s | 40 MB | 20.5x |
| libfyaml | 70 ms | 28 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 125 ms | 16 MB/s | 80 MB | 41.6x |
| yaml-cpp | 272 ms | 7 MB/s | 110 MB | 57.4x |
| PyYAML on libyaml (C) | 762 ms | 3 MB/s | 117 MB | 61.1x |

_2026-10-28; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf 80b75f1.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree._
