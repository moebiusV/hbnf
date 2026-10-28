**JSON** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.8 ms | 1143 MB/s | 15 MB | 7.1x |
| hbnf (C backend), typed tree | 4.2 ms | 480 MB/s | 8 MB | 3.4x |
| RapidJSON | 5.7 ms | 353 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 10 ms | 196 MB/s | 54 MB | 27.7x |
| cJSON | 12 ms | 163 MB/s | 17 MB | 8.1x |
| Python json | 13 ms | 154 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 16 ms | 128 MB/s | 20 MB | 9.8x |
| Jansson | 30 ms | 67 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 9.8 ms | 202 MB/s | 16 MB | 7.9x |
| tomlc17 | 40 ms | 50 MB/s | 17 MB | 8.4x |
| toml++ | 48 ms | 41 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 54 ms | 37 MB/s | 58 MB | 29.6x |
| Python tomllib | 257 ms | 8 MB/s | 26 MB | 12.8x |
| toml11 | 665 ms | 3 MB/s | 94 MB | 48.8x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| rapidyaml | 16 ms | 124 MB/s | 25 MB | 12.6x |
| hbnf (C backend), typed tree | 24 ms | 84 MB/s | 37 MB | 18.9x |
| libyaml | 40 ms | 50 MB/s | 41 MB | 20.7x |
| libfyaml | 71 ms | 28 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 128 ms | 16 MB/s | 81 MB | 42.1x |
| yaml-cpp | 284 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 790 ms | 3 MB/s | 117 MB | 61.1x |

_2026-10-28; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf 4a2e109.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes._
