| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 3000 | 1.9 MB | 278 ms | 53 ms | 57 ms | 4.8x | 40 MB | 40 MB |
| mustache | 25 files x 3000 | 1.1 MB | 65 ms | 26 ms | 17 ms | 3.7x | 42 MB | 21 MB |
| algol60 | 5 files x 1000 | 2.4 MB | 6184 ms | 108 ms | 92 ms | 67.3x | 73 MB | 51 MB |
| httpd | 1 files x 2000 | 1.6 MB | 1089 ms | 94 ms | 78 ms | 13.9x | 70 MB | 15 MB |
| relayd | 2 files x 2000 | 1.5 MB | 250 ms | 41 ms | 37 ms | 6.8x | 21 MB | 9 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.34 on the host, hbnf aaf9aa9; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
