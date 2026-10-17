| rules | input | parse time | rules/s | MB/s | peak RSS |
|---:|---:|---:|---:|---:|---:|
| 100000 | 9.18 MB | 532 ms | 188 K rules/s | 17 MB/s | 394 MB |
| 1000000 | 91.86 MB | 5.94 s | 168 K rules/s | 15 MB/s | 3.8 GB |

_Measured 2026-10-17 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.69 on the host, hbnf e8830cd; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
