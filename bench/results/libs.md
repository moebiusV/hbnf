**JSON** (2 MB, the same file for every tool; parse time, best of 5):

| tool | musl | glibc | peak RSS (glibc) |
|---|---:|---:|---:|
| simdjson (DOM) | 1.8 ms | 1.6 ms | 13 MB |
| RapidJSON | 5.3 ms | 4.8 ms | 9 MB |
| hbnf (C backend), typed tree | 13 ms | 10 ms | 15 MB |
| cJSON | 13 ms | 11 ms | 17 MB |
| serde_json (Rust) 1.0.154 | 21 ms | 15 ms | 20 MB |
| Jansson | 34 ms | 29 ms | 20 MB |

**TOML 1.0** (2 MB, the same file for every tool; parse time, best of 5):

| tool | musl | glibc | peak RSS (glibc) |
|---|---:|---:|---:|
| hbnf (C backend), typed tree | 30 ms | 20 ms | 23 MB |
| tomlc17 | 46 ms | 37 ms | 17 MB |
| toml++ | 49 ms | 45 ms | 26 MB |
| toml (Rust) 0.9.12+spec-1.1.0 | 63 ms | 51 ms | 58 MB |
| toml11 | 1342 ms | 663 ms | 94 MB |

**YAML 1.2** (2 MB, the same file for every tool; parse time, best of 5):

| tool | musl | glibc | peak RSS (glibc) |
|---|---:|---:|---:|
| rapidyaml | 16 ms | 15 ms | 27 MB |
| libyaml | 56 ms | 37 ms | 40 MB |
| libfyaml | 87 ms | 67 ms | 84 MB |
| hbnf (C backend), typed tree | 142 ms | 112 ms | 110 MB |
| yaml-cpp | 396 ms | 294 ms | 110 MB |

_2026-10-24; musl: musl libc (x86_64), gcc (Alpine 15.2.0) 15.2.0; glibc: 2.41, gcc (Debian 14.2.0-19) 14.2.0; `-O2`, same sources and flags; hbnf 0fc6d42.  simdjson is its DOM API; the C++ and Rust libraries build their own value types._
