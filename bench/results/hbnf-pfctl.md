| rules | input | parse time | rules/s | MB/s | peak RSS |
|---:|---:|---:|---:|---:|---:|
| 100000 | 9.18 MB | 87 ms | 1154 K rules/s | 106 MB/s | 116 MB |
| 1000000 | 91.86 MB | 1.06 s | 942 K rules/s | 87 MB/s | 1.1 GB |

_Measured 2026-11-05 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.27 on the host, hbnf c4d9370; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._
