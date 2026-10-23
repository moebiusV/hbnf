**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 24 ms | 4.2 M rules/s | 326 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 61 ms | 1.6 M rules/s | 126 MB/s | 23 MB |
| bison + flex | 7.68 MB | 62 ms | 1.6 M rules/s | 125 MB/s | 23 MB |
| peg/leg | 7.68 MB | 56 ms | 1.8 M rules/s | 137 MB/s | 30 MB |
| tree-sitter 0.27.1 | 7.68 MB | 365 ms | 0.3 M rules/s | 21 MB/s | 63 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 35 ms | | | 81 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 219 ms | 0.5 M rules/s | 35 MB/s | 201 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 115 ms | 0.9 M rules/s | 67 MB/s | 534 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 7.68 MB | 281 ms | 0.4 M rules/s | 27 MB/s | 273 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 230 ms | 4.3 M rules/s | 334 MB/s | 203 MB |
| byacc + flex | 76.86 MB | 614 ms | 1.6 M rules/s | 125 MB/s | 224 MB |
| bison + flex | 76.86 MB | 615 ms | 1.6 M rules/s | 125 MB/s | 224 MB |
| peg/leg | 76.86 MB | 563 ms | 1.8 M rules/s | 137 MB/s | 294 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2271 ms | 0.4 M rules/s | 34 MB/s | 620 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 353 ms | | | 804 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1262 ms | 0.8 M rules/s | 61 MB/s | 1433 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1134 ms | 0.9 M rules/s | 68 MB/s | 3101 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 76.86 MB | 1703 ms | 0.6 M rules/s | 45 MB/s | 2523 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 5.81 on the host, hbnf 23fc853; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
