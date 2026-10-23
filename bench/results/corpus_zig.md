| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 3000 | 1.9 MB | 470 ms | 85 ms | 98 ms | 4.8x | 40 MB | 40 MB |
| mustache | 25 files x 3000 | 1.1 MB | 71 ms | 29 ms | 20 ms | 3.5x | 42 MB | 21 MB |
| algol60 | 5 files x 1000 | 2.4 MB | 7230 ms | 98 ms | 85 ms | 85.0x | 73 MB | 53 MB |
| httpd | 1 files x 2000 | 1.6 MB | 1685 ms | 137 ms | 137 ms | 12.3x | 70 MB | 16 MB |
| relayd | 2 files x 2000 | 1.5 MB | 338 ms | 63 ms | 63 ms | 5.4x | 21 MB | 9 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.08 on the host, hbnf cd94a16; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
