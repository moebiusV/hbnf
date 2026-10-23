**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 24 ms | 4.1 M rules/s | 318 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 62 ms | 1.6 M rules/s | 124 MB/s | 23 MB |
| bison + flex | 7.68 MB | 79 ms | 1.3 M rules/s | 97 MB/s | 23 MB |
| tree-sitter 0.27.1 | 7.68 MB | 224 ms | 0.4 M rules/s | 34 MB/s | 63 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 252 ms | 0.4 M rules/s | 31 MB/s | 207 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 125 ms | 0.8 M rules/s | 61 MB/s | 545 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 258 ms | 3.9 M rules/s | 297 MB/s | 203 MB |
| byacc + flex | 76.86 MB | 625 ms | 1.6 M rules/s | 123 MB/s | 224 MB |
| bison + flex | 76.86 MB | 666 ms | 1.5 M rules/s | 115 MB/s | 224 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2271 ms | 0.4 M rules/s | 34 MB/s | 620 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1586 ms | 0.6 M rules/s | 48 MB/s | 1434 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1186 ms | 0.8 M rules/s | 65 MB/s | 3049 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.08 on the host, hbnf cd94a16; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
