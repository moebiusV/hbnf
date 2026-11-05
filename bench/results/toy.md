**100,000 rules** (7.68 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 15 ms | 6.8 M rules/s | 526 MB/s | 17 MB |
| byacc + flex | 7.68 MB | 52 ms | 1.9 M rules/s | 147 MB/s | 29 MB |
| bison + flex | 7.68 MB | 53 ms | 1.9 M rules/s | 146 MB/s | 29 MB |
| peg/leg | 7.68 MB | 42 ms | 2.4 M rules/s | 184 MB/s | 41 MB |
| tree-sitter 0.27.1 | 7.68 MB | 213 ms | 0.5 M rules/s | 36 MB/s | 58 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 31 ms | | | 76 MB |
| ANTLR 4 (Java), actions, cold JVM | 7.68 MB | 301 ms | 0.3 M rules/s | 25 MB/s | 217 MB |
| ANTLR 4 (Java), actions, warm JVM | 7.68 MB | 95 ms | 1.1 M rules/s | 81 MB/s | 471 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 7.68 MB | 366 ms | 0.3 M rules/s | 21 MB/s | 297 MB |

**1,000,000 rules** (76.86 MB, the same file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 148 ms | 6.8 M rules/s | 520 MB/s | 137 MB |
| byacc + flex | 76.86 MB | 523 ms | 1.9 M rules/s | 147 MB/s | 273 MB |
| bison + flex | 76.86 MB | 532 ms | 1.9 M rules/s | 144 MB/s | 273 MB |
| peg/leg | 76.86 MB | 421 ms | 2.4 M rules/s | 183 MB/s | 395 MB |
| tree-sitter 0.27.1 | 76.86 MB | 2164 ms | 0.5 M rules/s | 36 MB/s | 564 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 321 ms | | | 744 MB |
| ANTLR 4 (Java), actions, cold JVM | 76.86 MB | 1601 ms | 0.6 M rules/s | 48 MB/s | 1177 MB |
| ANTLR 4 (Java), actions, warm JVM | 76.86 MB | 1171 ms | 0.9 M rules/s | 66 MB/s | 2110 MB |
| ANTLR 4 (Java), parse tree, cold JVM | 76.86 MB | 3163 ms | 0.3 M rules/s | 24 MB/s | 2088 MB |

_Measured 2026-11-05 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.27 on the host, hbnf c4d9370; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._
