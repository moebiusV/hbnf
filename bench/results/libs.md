**JSON** (2 MB, the same file for every tool; parse time, best of 5):

| tool | musl | glibc | peak RSS (glibc) |
|---|---:|---:|---:|
| simdjson (DOM) | 1.9 ms | 1.9 ms | 14 MB |
| RapidJSON | 5.4 ms | 4.9 ms | 9 MB |
| hbnf (C backend), typed tree | 10 ms | 8.8 ms | 15 MB |
| cJSON | 13 ms | 11 ms | 17 MB |
| serde_json (Rust) 1.0.154 | 22 ms | 15 ms | 20 MB |
| Jansson | 34 ms | 30 ms | 20 MB |

**TOML 1.0** (2 MB, the same file for every tool; parse time, best of 5):

| tool | musl | glibc | peak RSS (glibc) |
|---|---:|---:|---:|
| hbnf (C backend), typed tree | 21 ms | 19 ms | 24 MB |
| tomlc17 | 46 ms | 37 ms | 17 MB |
| toml++ | 49 ms | 44 ms | 26 MB |
| toml (Rust) 0.9.12+spec-1.1.0 | 65 ms | 52 ms | 58 MB |
| toml11 | 1372 ms | 659 ms | 94 MB |

**YAML 1.2** (2 MB, the same file for every tool; parse time, best of 5):

| tool | musl | glibc | peak RSS (glibc) |
|---|---:|---:|---:|
| rapidyaml | 15 ms | 15 ms | 27 MB |
| libyaml | 57 ms | 37 ms | 40 MB |
| hbnf (C backend), typed tree | 59 ms | 56 ms | 58 MB |
| libfyaml | 90 ms | 68 ms | 84 MB |
| yaml-cpp | 406 ms | 284 ms | 110 MB |

_2026-10-24; musl: musl libc (x86_64), gcc (Alpine 15.2.0) 15.2.0; glibc: 2.41, gcc (Debian 14.2.0-19) 14.2.0; `-O2`, same sources and flags; hbnf 44f0853.  simdjson is its DOM API; the C++ and Rust libraries build their own value types._
