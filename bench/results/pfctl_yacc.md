**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 464 ms | 215 K rules/s | 20 MB/s | 172.6 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 9.18 MB | 413 ms | 242 K rules/s | 22 MB/s | 457.0 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 9.18 MB | 241 ms | 415 K rules/s | 38 MB/s | 132.5 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 4.63 s | 216 K rules/s | 20 MB/s | 1723.2 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 91.86 MB | 4.09 s | 245 K rules/s | 22 MB/s | 4565.7 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 91.86 MB | 2.41 s | 414 K rules/s | 38 MB/s | 1322.1 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.34 on the host, hbnf aaf9aa9; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
