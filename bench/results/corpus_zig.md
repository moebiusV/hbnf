| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 3000 | 1.9 MB | 304 ms | 57 ms | 62 ms | 4.9x | 40 MB | 40 MB |
| mustache | 25 files x 3000 | 1.1 MB | 69 ms | 28 ms | 19 ms | 3.7x | 42 MB | 21 MB |
| algol60 | 5 files x 1000 | 2.4 MB | 6528 ms | 110 ms | 98 ms | 66.9x | 72 MB | 51 MB |
| httpd | 1 files x 2000 | 1.6 MB | 1141 ms | 99 ms | 82 ms | 13.9x | 70 MB | 15 MB |
| relayd | 2 files x 2000 | 1.5 MB | 285 ms | 43 ms | 38 ms | 7.5x | 21 MB | 9 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.56 on the host, hbnf 2def6a4; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
