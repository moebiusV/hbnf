**JSON** (2.00 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| simdjson (DOM) | 1.7 ms | 1150 MB/s | 13 MB | 6.3x |
| hbnf (C backend), %emit tape | 2.0 ms | 990 MB/s | 7 MB | 2.8x |
| hbnf (C backend), typed tree | 3.4 ms | 581 MB/s | 8 MB | 3.4x |
| RapidJSON | 5.0 ms | 398 MB/s | 9 MB | 3.8x |
| Node JSON.parse | 9.6 ms | 208 MB/s | 54 MB | 27.6x |
| cJSON | 12 ms | 172 MB/s | 17 MB | 8.1x |
| Python json | 12 ms | 167 MB/s | 20 MB | 9.7x |
| serde_json (Rust) 1.0.154 | 15 ms | 133 MB/s | 20 MB | 9.9x |
| Jansson | 28 ms | 71 MB/s | 20 MB | 9.7x |

**TOML 1.0** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| hbnf (C backend), typed tree | 9.2 ms | 215 MB/s | 17 MB | 8.0x |
| tomlc17 | 38 ms | 52 MB/s | 17 MB | 8.3x |
| toml++ | 47 ms | 43 MB/s | 26 MB | 13.0x |
| toml (Rust) 0.9.12+spec-1.1.0 | 50 ms | 40 MB/s | 59 MB | 30.1x |
| Python tomllib | 246 ms | 8 MB/s | 26 MB | 12.9x |
| toml11 | 664 ms | 3 MB/s | 94 MB | 48.5x |

**YAML 1.2** (1.99 MB, the same file for every tool; best of up to 5 runs):

| tool | parse time | MB/s | peak RSS | RSS over the input |
|---|---:|---:|---:|---:|
| rapidyaml | 16 ms | 128 MB/s | 26 MB | 13.0x |
| hbnf (C backend), typed tree | 22 ms | 91 MB/s | 37 MB | 18.9x |
| libyaml | 38 ms | 53 MB/s | 41 MB | 20.6x |
| libfyaml | 68 ms | 29 MB/s | 84 MB | 43.6x |
| js-yaml (Node) | 121 ms | 16 MB/s | 82 MB | 42.2x |
| yaml-cpp | 264 ms | 8 MB/s | 110 MB | 57.4x |
| PyYAML on libyaml (C) | 738 ms | 3 MB/s | 117 MB | 61.1x |

_2026-10-28; glibc 2.41, gcc (Debian 14.2.0-19) 14.2.0, node 20.19.2, Python 3.13.5; `-O2`, the same sources and flags for every native library; hbnf 4e93ce8.  simdjson is its DOM API; the C++ and Rust libraries, Python, Node and the YAML parsers build their own value types, and hbnf builds the typed tree its grammar describes, except in the row that says `%emit tape`: that grammar writes a flat tape of 64-bit words and builds no tree._
