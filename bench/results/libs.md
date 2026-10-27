**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 2.3 ms | 873 MB/s | 12 MB | 5.7x |
| RapidJSON | 4.8 ms | 417 MB/s | 9 MB | 3.9x |
| hbnf (C backend), typed tree | 5.9 ms | 341 MB/s | 8 MB | 3.3x |
| Node JSON.parse | 8.2 ms | 244 MB/s | 55 MB | 28.0x |
| cJSON | 12 ms | 173 MB/s | 17 MB | 8.2x |
| Python json | 12 ms | 165 MB/s | 20 MB | 9.8x |
| serde_json (Rust) 1.0.154 | 15 ms | 136 MB/s | 20 MB | 9.9x |
| Jansson | 30 ms | 67 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 14 ms | 146 MB/s | 17 MB | 8.0x |
| tomlc17 | 38 ms | 52 MB/s | 17 MB | 8.4x |
| toml++ | 45 ms | 44 MB/s | 26 MB | 13.2x |
| toml (Rust) 0.9.12+spec-1.1.0 | 60 ms | 33 MB/s | 57 MB | 29.5x |
| Python tomllib | 254 ms | 8 MB/s | 26 MB | 13.0x |
| toml11 | 663 ms | 3 MB/s | 94 MB | 48.9x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| rapidyaml | 20 ms | 99 MB/s | 25 MB | 12.5x |
| libyaml | 41 ms | 49 MB/s | 39 MB | 19.7x |
| hbnf (C backend), typed tree | 42 ms | 47 MB/s | 46 MB | 23.4x |
| libfyaml | 68 ms | 29 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 80 ms | 25 MB/s | 80 MB | 41.5x |
| yaml-cpp | 312 ms | 6 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 717 ms | 3 MB/s | 117 MB | 61.0x |

_2026-10-24; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf e1f0895.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes._
