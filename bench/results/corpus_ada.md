| corpus | input | parsed | time, parser template before | time now | faster | memory |
|---|---|---:|---:|---:|---:|---:|
| json | 26 files x 300 | 0.2 MB | 1038 ms | 1062 ms | 0.98x | 20 MB |
| mustache | 25 files x 300 | 0.1 MB | 939 ms | 942 ms | 1.00x | 9 MB |
| httpd | 1 files x 200 | 0.2 MB | 1842 ms | 2029 ms | 0.91x | 7 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.08 on the host, hbnf cd94a16; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
