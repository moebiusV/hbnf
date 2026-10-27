**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 18 ms | 5.5 M rules/s | 425 MB/s | 15 MB |
| byacc + flex | 7.68 MB | 56 ms | 1.8 M rules/s | 138 MB/s | 29 MB |
| bison + flex | 7.68 MB | 58 ms | 1.7 M rules/s | 133 MB/s | 29 MB |
| tree-sitter 0.27.1 | 7.68 MB | 222 ms | 0.4 M rules/s | 35 MB/s | 58 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 257 ms | 0.4 M rules/s | 30 MB/s | 223 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 103 ms | 1.0 M rules/s | 75 MB/s | 606 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 184 ms | 5.4 M rules/s | 419 MB/s | 136 MB |
| byacc + flex | 76.86 MB | 564 ms | 1.8 M rules/s | 136 MB/s | 273 MB |
| bison + flex | 76.86 MB | 558 ms | 1.8 M rules/s | 138 MB/s | 273 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2303 ms | 0.4 M rules/s | 33 MB/s | 564 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1196 ms | 0.8 M rules/s | 64 MB/s | 1446 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1163 ms | 0.9 M rules/s | 66 MB/s | 2844 MB |

_Measured 2026-10-27 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.11 on the host, hbnf 56e8c78; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._
