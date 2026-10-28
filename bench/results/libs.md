**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.8 ms | 1099 MB/s | 14 MB | 6.6x |
| hbnf (C backend), %emit tape | 3.4 ms | 585 MB/s | 6 MB | 2.5x |
| hbnf (C backend), typed tree | 4.1 ms | 491 MB/s | 8 MB | 3.3x |
| RapidJSON | 5.1 ms | 395 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 9.6 ms | 208 MB/s | 55 MB | 27.9x |
| cJSON | 12 ms | 174 MB/s | 17 MB | 8.1x |
| Python json | 12 ms | 174 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 13 ms | 148 MB/s | 20 MB | 9.9x |
| Jansson | 29 ms | 70 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 9.3 ms | 215 MB/s | 17 MB | 8.0x |
| tomlc17 | 38 ms | 52 MB/s | 17 MB | 8.3x |
| toml++ | 45 ms | 45 MB/s | 26 MB | 13.0x |
| toml (Rust) 0.9.12+spec-1.1.0 | 50 ms | 40 MB/s | 58 MB | 30.0x |
| Python tomllib | 254 ms | 8 MB/s | 26 MB | 12.9x |
| toml11 | 655 ms | 3 MB/s | 95 MB | 49.3x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| rapidyaml | 15 ms | 131 MB/s | 26 MB | 13.0x |
| hbnf (C backend), typed tree | 22 ms | 89 MB/s | 37 MB | 18.9x |
| libyaml | 38 ms | 53 MB/s | 41 MB | 20.8x |
| libfyaml | 68 ms | 29 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 120 ms | 17 MB/s | 81 MB | 41.9x |
| yaml-cpp | 261 ms | 8 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 695 ms | 3 MB/s | 117 MB | 61.0x |

_2026-10-28; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf c087bbc.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree._
