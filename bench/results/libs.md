**JSON** (2.00 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.6 ms | 1212 MB/s | 14 MB | 6.5x |
| hbnf (C backend), typed tree | 4.0 ms | 498 MB/s | 8 MB | 3.4x |
| RapidJSON | 4.7 ms | 426 MB/s | 9 MB | 3.8x |
| Node JSON.parse | 9.2 ms | 217 MB/s | 55 MB | 27.8x |
| cJSON | 11 ms | 184 MB/s | 17 MB | 8.1x |
| Python json | 11 ms | 180 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 13 ms | 157 MB/s | 20 MB | 9.8x |
| Jansson | 27 ms | 73 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 8.6 ms | 233 MB/s | 17 MB | 8.0x |
| tomlc17 | 36 ms | 55 MB/s | 17 MB | 8.3x |
| toml++ | 42 ms | 47 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 48 ms | 41 MB/s | 57 MB | 29.5x |
| Python tomllib | 240 ms | 8 MB/s | 26 MB | 12.8x |
| toml11 | 626 ms | 3 MB/s | 94 MB | 48.5x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 9 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| rapidyaml | 15 ms | 132 MB/s | 26 MB | 13.1x |
| hbnf (C backend), typed tree | 24 ms | 83 MB/s | 41 MB | 20.9x |
| libyaml | 36 ms | 55 MB/s | 40 MB | 20.5x |
| libfyaml | 65 ms | 31 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 115 ms | 17 MB/s | 80 MB | 41.5x |
| yaml-cpp | 271 ms | 7 MB/s | 110 MB | 57.3x |
| PyYAML on libyaml (C) | 679 ms | 3 MB/s | 117 MB | 61.1x |

_2026-10-27; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf e3025f7.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes._
