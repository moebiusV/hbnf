**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 674 ms | 148 K rules/s | 14 MB/s | 173.1 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 9.18 MB | 714 ms | 140 K rules/s | 13 MB/s | 457.1 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 9.18 MB | 482 ms | 208 K rules/s | 19 MB/s | 132.6 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 6.75 s | 148 K rules/s | 14 MB/s | 1723.7 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 91.86 MB | 7.28 s | 137 K rules/s | 13 MB/s | 4565.7 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 91.86 MB | 4.86 s | 206 K rules/s | 19 MB/s | 1322.3 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
