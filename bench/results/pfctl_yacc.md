**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 1.16 s | 87 K rules/s | 8 MB/s | 150.0 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 9.18 MB | 312 ms | 320 K rules/s | 29 MB/s | 448.4 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 9.18 MB | 163 ms | 612 K rules/s | 56 MB/s | 148.2 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 11.65 s | 86 K rules/s | 8 MB/s | 1481.9 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 91.86 MB | 3.09 s | 324 K rules/s | 30 MB/s | 4468.3 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 91.86 MB | 1.60 s | 625 K rules/s | 57 MB/s | 1468.2 MB |

_Measured 2026-10-27 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 7.32 on the host, hbnf 56e8c78; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._
