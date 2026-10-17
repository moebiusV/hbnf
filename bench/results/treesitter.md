**100,000 rules** (the same 7.68 MB file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 7.68 MB | 25 ms | 3.9 M rules/s | 303 MB/s | 21 MB |
| tree-sitter 0.27.1 | 7.68 MB | 229 ms | 0.4 M rules/s | 34 MB/s | 63 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 51 ms | | | 81 MB |

**1,000,000 rules** (the same 76.86 MB file for every tool):

| tool | input | parse time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| hbnf (C backend) | 76.86 MB | 257 ms | 3.9 M rules/s | 300 MB/s | 204 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit 0.27.1 | 76.86 MB | 3543 ms | 0.3 M rules/s | 22 MB/s | 620 MB |
| tree-sitter 0.27.1, re-parse after a one-byte edit | (edit) | 371 ms | | | 804 MB |

_Measured 2026-10-17 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 5.50 on the host, hbnf e8830cd; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
