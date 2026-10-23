**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 480 ms | 209 K rules/s | 19 MB/s | 172.9 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 9.18 MB | 453 ms | 221 K rules/s | 20 MB/s | 457.1 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 9.18 MB | 280 ms | 357 K rules/s | 33 MB/s | 132.6 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 4.71 s | 212 K rules/s | 19 MB/s | 1723.4 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 91.86 MB | 4.50 s | 222 K rules/s | 20 MB/s | 4565.4 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 91.86 MB | 2.79 s | 359 K rules/s | 33 MB/s | 1322.2 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 5.81 on the host, hbnf 23fc853; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
