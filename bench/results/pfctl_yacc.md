**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 480 ms | 208 K rules/s | 19 MB/s | 173.0 MB |
| hbnf pfctl grammar (`--conf`, typed tree) | 9.18 MB | 568 ms | 176 K rules/s | 16 MB/s | 394.2 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 4.88 s | 205 K rules/s | 19 MB/s | 1723.5 MB |
| hbnf pfctl grammar (`--conf`, typed tree) | 91.86 MB | 5.70 s | 175 K rules/s | 16 MB/s | 3937.7 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.48 on the host, hbnf 0d2aa64; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
