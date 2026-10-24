**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 480 ms | 208 K rules/s | 19 MB/s | 172.9 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 9.18 MB | 375 ms | 267 K rules/s | 24 MB/s | 457.1 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 9.18 MB | 200 ms | 499 K rules/s | 46 MB/s | 132.7 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 4.76 s | 210 K rules/s | 19 MB/s | 1723.5 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 91.86 MB | 3.73 s | 268 K rules/s | 25 MB/s | 4565.6 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 91.86 MB | 2.00 s | 500 K rules/s | 46 MB/s | 1321.9 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
