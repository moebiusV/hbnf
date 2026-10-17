**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 26 ms | 3.8 M rules/s | 293 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 63 ms | 1.6 M rules/s | 121 MB/s | 23 MB |
| bison + flex | 7.68 MB | 84 ms | 1.2 M rules/s | 92 MB/s | 23 MB |
| tree-sitter 0.27.1 | 7.68 MB | 226 ms | 0.4 M rules/s | 34 MB/s | 63 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 222 ms | 0.5 M rules/s | 35 MB/s | 204 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 111 ms | 0.9 M rules/s | 69 MB/s | 530 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 266 ms | 3.8 M rules/s | 289 MB/s | 204 MB |
| byacc + flex | 76.86 MB | 628 ms | 1.6 M rules/s | 122 MB/s | 224 MB |
| bison + flex | 76.86 MB | 746 ms | 1.3 M rules/s | 103 MB/s | 224 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2302 ms | 0.4 M rules/s | 33 MB/s | 620 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1278 ms | 0.8 M rules/s | 60 MB/s | 1438 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1219 ms | 0.8 M rules/s | 63 MB/s | 2725 MB |

_Measured 2026-10-17 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.69 on the host, hbnf e8830cd; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
