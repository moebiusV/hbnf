**100,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 9.18 MB | 1.08 s | 93 K rules/s | 9 MB/s | 149.9 MB |
| hbnf pfctl grammar (`--no-compact`, typed tree) | 9.18 MB | 154 ms | 649 K rules/s | 60 MB/s | 283.4 MB |
| hbnf pfctl grammar (compact nodes, the default) | 9.18 MB | 113 ms | 886 K rules/s | 81 MB/s | 113.9 MB |

**1,000,000 filter rules** (one `pass in quick ... keep state` line each, the same file for both):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---|---:|---:|---:|---:|
| OpenBSD pfctl parse.y, byacc (fills struct pf_rule) | 91.86 MB | 11.00 s | 91 K rules/s | 8 MB/s | 1481.9 MB |
| hbnf pfctl grammar (`--no-compact`, typed tree) | 91.86 MB | 1.46 s | 686 K rules/s | 63 MB/s | 2817.2 MB |
| hbnf pfctl grammar (compact nodes, the default) | 91.86 MB | 1.10 s | 909 K rules/s | 84 MB/s | 1123.3 MB |

_Measured 2026-11-05 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.27 on the host, hbnf c4d9370; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._
