**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 462 ms | 217 K rules/s | 20 MB/s | 172.8 MB |
| hbnf pfctl grammar (`--conf`, typed tree) | 9.18 MB | 448 ms | 223 K rules/s | 21 MB/s | 457.0 MB |
| hbnf pfctl grammar (`--conf --compact`) | 9.18 MB | 281 ms | 356 K rules/s | 33 MB/s | 144.2 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 4.60 s | 217 K rules/s | 20 MB/s | 1723.4 MB |
| hbnf pfctl grammar (`--conf`, typed tree) | 91.86 MB | 4.47 s | 224 K rules/s | 21 MB/s | 4565.7 MB |
| hbnf pfctl grammar (`--conf --compact`) | 91.86 MB | 2.80 s | 357 K rules/s | 33 MB/s | 1438.3 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.44 on the host, hbnf 3cedc66; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
