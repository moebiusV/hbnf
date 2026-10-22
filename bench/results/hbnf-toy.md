**100,000 rules** (7.68 MB):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 24 ms | 4.1 M rules/s | 318 MB/s | 21 MB |

**1,000,000 rules** (76.86 MB):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 242 ms | 4.1 M rules/s | 318 MB/s | 204 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
