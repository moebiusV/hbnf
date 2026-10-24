**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 24 ms | 4.1 M rules/s | 317 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 61 ms | 1.6 M rules/s | 126 MB/s | 23 MB |
| bison + flex | 7.68 MB | 62 ms | 1.6 M rules/s | 124 MB/s | 23 MB |
| tree-sitter 0.27.1 | 7.68 MB | 220 ms | 0.5 M rules/s | 35 MB/s | 63 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 202 ms | 0.5 M rules/s | 38 MB/s | 197 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 115 ms | 0.9 M rules/s | 67 MB/s | 530 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 238 ms | 4.2 M rules/s | 322 MB/s | 204 MB |
| byacc + flex | 76.86 MB | 611 ms | 1.6 M rules/s | 126 MB/s | 224 MB |
| bison + flex | 76.86 MB | 623 ms | 1.6 M rules/s | 123 MB/s | 224 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2214 ms | 0.5 M rules/s | 35 MB/s | 620 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1264 ms | 0.8 M rules/s | 61 MB/s | 1427 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1020 ms | 1.0 M rules/s | 75 MB/s | 2854 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.34 on the host, hbnf aaf9aa9; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
