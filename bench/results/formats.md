**JSON** (2.00 MB, the same file for every tool):

| tool | parse time | MB/s | peak RSS |
|---|---:|---:|---:|
| hbnf (C backend), typed tree | 13 ms | 151 MB/s | 15 MB |
| Python 3.14.8 json | 16 ms | 122 MB/s | 19 MB |
| Node 24.18.1 JSON.parse | 8.5 ms | 235 MB/s | 51 MB |

**TOML 1.0** (1.99 MB, the same file for every tool):

| tool | parse time | MB/s | peak RSS |
|---|---:|---:|---:|
| hbnf (C backend), typed tree | 30 ms | 65 MB/s | 24 MB |
| Python tomllib | 278 ms | 7 MB/s | 23 MB |

**YAML 1.2** (1.99 MB, the same file for every tool):

| tool | parse time | MB/s | peak RSS |
|---|---:|---:|---:|
| hbnf (C backend), typed tree | 148 ms | 13 MB/s | 119 MB |
| PyYAML 6.0.3 on libyaml (C) | 698 ms | 3 MB/s | 114 MB |
| PyYAML, pure Python | 3.44 s | 1 MB/s | 162 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
