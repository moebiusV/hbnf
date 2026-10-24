| rules | input | parse time | rules/s | MB/s | peak RSS |
|---:|---:|---:|---:|---:|---:|
| 100000 | 9.18 MB | 200 ms | 501 K rules/s | 46 MB/s | 133 MB |
| 1000000 | 91.86 MB | 1.96 s | 510 K rules/s | 47 MB/s | 1.3 GB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
