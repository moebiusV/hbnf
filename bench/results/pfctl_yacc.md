**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 467 ms | 214 K rules/s | 20 MB/s | 173.0 MB |
| hbnf pfctl grammar (`--conf`, typed tree) | 9.18 MB | 451 ms | 222 K rules/s | 20 MB/s | 457.0 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 4.64 s | 216 K rules/s | 20 MB/s | 1723.4 MB |
| hbnf pfctl grammar (`--conf`, typed tree) | 91.86 MB | 4.62 s | 217 K rules/s | 20 MB/s | 4565.7 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.45 on the host, hbnf a1fec7f; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
