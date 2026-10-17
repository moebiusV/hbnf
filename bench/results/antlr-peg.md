**100,000 rules** (the same 7.68 MB file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 25 ms | 3.9 M rules/s | 303 MB/s | 21 MB |
| peg/leg | 7.68 MB | 94 ms | 1.1 M rules/s | 82 MB/s | 30 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 267 ms | 0.4 M rules/s | 29 MB/s | 197 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 164 ms | 0.6 M rules/s | 47 MB/s | 563 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 7.68 MB | 323 ms | 0.3 M rules/s | 24 MB/s | 279 MB |

**1,000,000 rules** (the same 76.86 MB file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 257 ms | 3.9 M rules/s | 300 MB/s | 204 MB |
| peg/leg | 76.86 MB | 889 ms | 1.1 M rules/s | 86 MB/s | 294 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1710 ms | 0.6 M rules/s | 45 MB/s | 1448 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1425 ms | 0.7 M rules/s | 54 MB/s | 2861 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 76.86 MB | 2159 ms | 0.5 M rules/s | 36 MB/s | 2378 MB |

_Measured 2026-10-17 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 5.50 on the host, hbnf e8830cd; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
