**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 479 ms | 209 K rules/s | 19 MB/s | 172.9 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 9.18 MB | 456 ms | 219 K rules/s | 20 MB/s | 457.1 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 9.18 MB | 282 ms | 355 K rules/s | 33 MB/s | 132.5 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 4.84 s | 207 K rules/s | 19 MB/s | 1723.5 MB |
| hbnf pfctl grammar (`--conf --no-compact`, typed tree) | 91.86 MB | 5.40 s | 185 K rules/s | 17 MB/s | 4565.7 MB |
| hbnf pfctl grammar (`--conf`, compact nodes, the default) | 91.86 MB | 3.01 s | 332 K rules/s | 30 MB/s | 1322.0 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.08 on the host, hbnf cd94a16; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
