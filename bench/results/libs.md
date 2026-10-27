**JSON** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.7 ms | 1184 MB/s | 13 MB | 6.1x |
| hbnf (C backend), typed tree | 4.5 ms | 448 MB/s | 8 MB | 3.3x |
| RapidJSON | 4.9 ms | 410 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 8.8 ms | 227 MB/s | 55 MB | 28.1x |
| cJSON | 11 ms | 179 MB/s | 17 MB | 8.2x |
| Python json | 12 ms | 169 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 13 ms | 151 MB/s | 20 MB | 9.8x |
| Jansson | 29 ms | 69 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 10 ms | 194 MB/s | 17 MB | 8.0x |
| tomlc17 | 38 ms | 53 MB/s | 17 MB | 8.3x |
| toml++ | 44 ms | 45 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 49 ms | 41 MB/s | 57 MB | 29.5x |
| Python tomllib | 244 ms | 8 MB/s | 26 MB | 12.8x |
| toml11 | 657 ms | 3 MB/s | 94 MB | 48.8x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| rapidyaml | 15 ms | 133 MB/s | 27 MB | 13.3x |
| hbnf (C backend), typed tree | 29 ms | 69 MB/s | 41 MB | 20.9x |
| libyaml | 37 ms | 54 MB/s | 40 MB | 20.4x |
| libfyaml | 66 ms | 30 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 108 ms | 18 MB/s | 80 MB | 41.5x |
| yaml-cpp | 302 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 710 ms | 3 MB/s | 117 MB | 60.9x |

_2026-10-27; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf 8c55abe.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes._
