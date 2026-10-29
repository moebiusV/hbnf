**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.6 ms | 1258 MB/s | 13 MB | 6.1x |
| hbnf (C backend), %emit tape | 1.7 ms | 1156 MB/s | 5 MB | 1.8x |
| hbnf (C backend), typed tree | 1.9 ms | 1031 MB/s | 7 MB | 2.9x |
| RapidJSON | 5.0 ms | 400 MB/s | 9 MB | 3.8x |
| Node JSON.parse | 9.4 ms | 212 MB/s | 55 MB | 27.8x |
| cJSON | 11 ms | 182 MB/s | 17 MB | 8.1x |
| Python json | 12 ms | 172 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 15 ms | 138 MB/s | 20 MB | 9.8x |
| Jansson | 28 ms | 72 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 4.7 ms | 427 MB/s | 11 MB | 4.9x |
| hbnf (C backend), %emit tape | 4.7 ms | 426 MB/s | 7 MB | 2.9x |
| tomlc17 | 37 ms | 53 MB/s | 17 MB | 8.3x |
| toml++ | 45 ms | 44 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 50 ms | 40 MB/s | 59 MB | 30.1x |
| Python tomllib | 248 ms | 8 MB/s | 26 MB | 12.9x |
| toml11 | 638 ms | 3 MB/s | 93 MB | 48.4x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), %emit tape | 6.9 ms | 289 MB/s | 5 MB | 1.9x |
| hbnf (C backend), typed tree | 8.8 ms | 226 MB/s | 29 MB | 14.6x |
| rapidyaml | 15 ms | 137 MB/s | 25 MB | 12.5x |
| libyaml | 37 ms | 54 MB/s | 41 MB | 20.9x |
| libfyaml | 67 ms | 30 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 118 ms | 17 MB/s | 81 MB | 41.9x |
| yaml-cpp | 279 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 682 ms | 3 MB/s | 117 MB | 61.1x |

_2026-10-29; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf bad5b34.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree._
