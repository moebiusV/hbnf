**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 480 ms | 208 K rules/s | 19 MB/s | 172.9 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 9.18 MB | 458 ms | 218 K rules/s | 20 MB/s | 456.9 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 9.18 MB | 288 ms | 347 K rules/s | 32 MB/s | 144.2 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 4.68 s | 214 K rules/s | 20 MB/s | 1723.4 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 91.86 MB | 4.60 s | 217 K rules/s | 20 MB/s | 4565.7 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 91.86 MB | 2.85 s | 351 K rules/s | 32 MB/s | 1438.2 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.90 on the host, hbnf b27ed85; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
