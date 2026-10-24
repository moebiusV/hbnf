| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 3000 | 1.9 MB | 275 ms | 49 ms | 54 ms | 5.1x | 64 MB | 65 MB |
| mustache | 25 files x 3000 | 1.1 MB | 58 ms | 19 ms | 15 ms | 3.8x | 42 MB | 21 MB |
| algol60 | 5 files x 1000 | 2.4 MB | 6282 ms | 88 ms | 82 ms | 76.4x | 73 MB | 52 MB |
| httpd | 1 files x 2000 | 1.6 MB | 1093 ms | 80 ms | 79 ms | 13.8x | 71 MB | 15 MB |
| relayd | 2 files x 2000 | 1.5 MB | 252 ms | 39 ms | 37 ms | 6.7x | 22 MB | 9 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
