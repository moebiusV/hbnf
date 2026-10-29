**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.4 ms | 1379 MB/s | 14 MB | 6.7x |
| hbnf (C backend), %emit tape | 2.0 ms | 1010 MB/s | 7 MB | 2.9x |
| hbnf (C backend), typed tree | 2.3 ms | 858 MB/s | 9 MB | 3.9x |
| RapidJSON | 4.9 ms | 408 MB/s | 9 MB | 3.9x |
| Node JSON.parse | 9.6 ms | 208 MB/s | 54 MB | 27.6x |
| cJSON | 11 ms | 175 MB/s | 17 MB | 8.1x |
| Python json | 12 ms | 163 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 15 ms | 136 MB/s | 20 MB | 9.8x |
| Jansson | 28 ms | 72 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 6.4 ms | 310 MB/s | 17 MB | 8.1x |
| tomlc17 | 38 ms | 52 MB/s | 17 MB | 8.3x |
| toml++ | 45 ms | 44 MB/s | 26 MB | 13.1x |
| toml (Rust) 0.9.12+spec-1.1.0 | 50 ms | 40 MB/s | 58 MB | 30.0x |
| Python tomllib | 255 ms | 8 MB/s | 26 MB | 13.0x |
| toml11 | 666 ms | 3 MB/s | 94 MB | 48.8x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 15 ms | 136 MB/s | 39 MB | 19.8x |
| rapidyaml | 15 ms | 129 MB/s | 26 MB | 12.7x |
| libyaml | 38 ms | 53 MB/s | 39 MB | 19.8x |
| libfyaml | 68 ms | 29 MB/s | 84 MB | 43.7x |
| js-yaml (Node) | 122 ms | 16 MB/s | 81 MB | 42.2x |
| yaml-cpp | 275 ms | 7 MB/s | 110 MB | 57.2x |
| PyYAML on libyaml (C) | 741 ms | 3 MB/s | 117 MB | 61.1x |

_2026-10-28; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf 60093b6.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree._
