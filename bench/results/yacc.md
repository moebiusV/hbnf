**100,000 rules** (the same 7.68 MB file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 25 ms | 3.9 M rules/s | 303 MB/s | 21 MB |
| byacc + flex | 7.68 MB | 62 ms | 1.6 M rules/s | 124 MB/s | 23 MB |
| bison + flex | 7.68 MB | 62 ms | 1.6 M rules/s | 125 MB/s | 23 MB |

**1,000,000 rules** (the same 76.86 MB file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 257 ms | 3.9 M rules/s | 300 MB/s | 204 MB |
| byacc + flex | 76.86 MB | 611 ms | 1.6 M rules/s | 126 MB/s | 224 MB |
| bison + flex | 76.86 MB | 628 ms | 1.6 M rules/s | 122 MB/s | 224 MB |

_Measured 2026-10-17 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 5.50 on the host, hbnf e8830cd; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
