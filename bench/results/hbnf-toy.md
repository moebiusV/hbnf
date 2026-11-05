**100,000 rules** (7.68 MB):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 15 ms | 6.8 M rules/s | 526 MB/s | 17 MB |

**1,000,000 rules** (76.86 MB):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 148 ms | 6.8 M rules/s | 520 MB/s | 137 MB |

_Measured 2026-11-05 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.27 on the host, hbnf c4d9370; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._
