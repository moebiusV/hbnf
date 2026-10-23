| rules | input | parse time | rules/s | MB/s | peak RSS |
|---:|---:|---:|---:|---:|---:|
| 100000 | 9.18 MB | 304 ms | 329 K rules/s | 30 MB/s | 133 MB |
| 1000000 | 91.86 MB | 2.86 s | 349 K rules/s | 32 MB/s | 1.3 GB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.08 on the host, hbnf cd94a16; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
