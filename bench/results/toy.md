**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 24 ms | 4.2 M rules/s | 325 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 61 ms | 1.6 M rules/s | 125 MB/s | 23 MB |
| bison + flex | 7.68 MB | 61 ms | 1.6 M rules/s | 126 MB/s | 23 MB |
| peg/leg | 7.68 MB | 57 ms | 1.8 M rules/s | 136 MB/s | 30 MB |
| tree-sitter 0.27.1 | 7.68 MB | 221 ms | 0.5 M rules/s | 35 MB/s | 63 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 34 ms | | | 81 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 207 ms | 0.5 M rules/s | 37 MB/s | 197 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 110 ms | 0.9 M rules/s | 70 MB/s | 530 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 7.68 MB | 252 ms | 0.4 M rules/s | 31 MB/s | 275 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 236 ms | 4.2 M rules/s | 325 MB/s | 204 MB |
| byacc + flex | 76.86 MB | 612 ms | 1.6 M rules/s | 126 MB/s | 224 MB |
| bison + flex | 76.86 MB | 619 ms | 1.6 M rules/s | 124 MB/s | 224 MB |
| peg/leg | 76.86 MB | 561 ms | 1.8 M rules/s | 137 MB/s | 294 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2176 ms | 0.5 M rules/s | 35 MB/s | 620 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 353 ms | | | 804 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1302 ms | 0.8 M rules/s | 59 MB/s | 1426 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1125 ms | 0.9 M rules/s | 68 MB/s | 3027 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 76.86 MB | 1571 ms | 0.6 M rules/s | 49 MB/s | 2511 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
