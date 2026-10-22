**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 24 ms | 4.1 M rules/s | 318 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 68 ms | 1.5 M rules/s | 112 MB/s | 23 MB |
| bison + flex | 7.68 MB | 63 ms | 1.6 M rules/s | 121 MB/s | 23 MB |
| tree-sitter 0.27.1 | 7.68 MB | 227 ms | 0.4 M rules/s | 34 MB/s | 63 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 223 ms | 0.4 M rules/s | 34 MB/s | 207 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 123 ms | 0.8 M rules/s | 62 MB/s | 582 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 242 ms | 4.1 M rules/s | 318 MB/s | 204 MB |
| byacc + flex | 76.86 MB | 685 ms | 1.5 M rules/s | 112 MB/s | 224 MB |
| bison + flex | 76.86 MB | 633 ms | 1.6 M rules/s | 121 MB/s | 224 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2294 ms | 0.4 M rules/s | 34 MB/s | 620 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1244 ms | 0.8 M rules/s | 62 MB/s | 1395 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1651 ms | 0.6 M rules/s | 47 MB/s | 3011 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
