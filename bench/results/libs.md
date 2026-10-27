**JSON** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.9 ms | 1081 MB/s | 13 MB | 6.3x |
| RapidJSON | 4.8 ms | 416 MB/s | 9 MB | 3.9x |
| hbnf (C backend), typed tree | 5.1 ms | 391 MB/s | 8 MB | 3.3x |
| Node JSON.parse | 8.7 ms | 231 MB/s | 54 MB | 27.8x |
| cJSON | 11 ms | 180 MB/s | 17 MB | 8.1x |
| Python json | 11 ms | 177 MB/s | 20 MB | 9.6x |
| serde_json (Rust) 1.0.154 | 13 ms | 149 MB/s | 20 MB | 9.8x |
| Jansson | 29 ms | 68 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 12 ms | 160 MB/s | 17 MB | 8.0x |
| tomlc17 | 36 ms | 55 MB/s | 17 MB | 8.3x |
| toml++ | 44 ms | 45 MB/s | 26 MB | 13.0x |
| toml (Rust) 0.9.12+spec-1.1.0 | 48 ms | 41 MB/s | 57 MB | 29.5x |
| Python tomllib | 240 ms | 8 MB/s | 26 MB | 12.8x |
| toml11 | 628 ms | 3 MB/s | 94 MB | 48.8x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| rapidyaml | 15 ms | 136 MB/s | 25 MB | 12.4x |
| hbnf (C backend), typed tree | 32 ms | 62 MB/s | 41 MB | 20.9x |
| libyaml | 36 ms | 55 MB/s | 41 MB | 20.8x |
| libfyaml | 66 ms | 30 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 104 ms | 19 MB/s | 80 MB | 41.3x |
| yaml-cpp | 285 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 694 ms | 3 MB/s | 117 MB | 61.1x |

_2026-10-27; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf 9da3c7f.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes._
