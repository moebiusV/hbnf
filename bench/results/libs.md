**JSON** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.9 ms | 1047 MB/s | 14 MB | 6.4x |
| hbnf (C backend), typed tree | 3.7 ms | 535 MB/s | 8 MB | 3.4x |
| RapidJSON | 5.1 ms | 390 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 9.4 ms | 213 MB/s | 55 MB | 27.9x |
| Python json | 11 ms | 176 MB/s | 20 MB | 9.7x |
| cJSON | 12 ms | 172 MB/s | 17 MB | 8.1x |
| serde_json (Rust) 1.0.154 | 14 ms | 142 MB/s | 20 MB | 9.8x |
| Jansson | 29 ms | 68 MB/s | 20 MB | 9.8x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 9.4 ms | 213 MB/s | 17 MB | 8.0x |
| tomlc17 | 37 ms | 54 MB/s | 17 MB | 8.3x |
| toml++ | 46 ms | 43 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 49 ms | 41 MB/s | 58 MB | 29.6x |
| Python tomllib | 240 ms | 8 MB/s | 26 MB | 12.9x |
| toml11 | 650 ms | 3 MB/s | 93 MB | 48.4x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| rapidyaml | 15 ms | 133 MB/s | 27 MB | 13.3x |
| hbnf (C backend), typed tree | 24 ms | 84 MB/s | 37 MB | 19.0x |
| libyaml | 37 ms | 54 MB/s | 39 MB | 19.9x |
| libfyaml | 66 ms | 30 MB/s | 84 MB | 43.7x |
| js-yaml (Node) | 120 ms | 17 MB/s | 81 MB | 41.9x |
| yaml-cpp | 257 ms | 8 MB/s | 110 MB | 57.4x |
| PyYAML on libyaml (C) | 691 ms | 3 MB/s | 118 MB | 61.1x |

_2026-10-27; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf e5a464e.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes._
