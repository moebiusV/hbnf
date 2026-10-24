| corpus | input | parsed | time before (exceptions) | time now | faster | memory |
|---|---|---:|---:|---:|---:|---:|
| json | 26 files x 300 | 0.2 MB | 1070 ms | 79 ms | 13.52x | 23 MB |
| mustache | 25 files x 300 | 0.1 MB | 580 ms | 25 ms | 22.99x | 9 MB |
| httpd | 1 files x 200 | 0.2 MB | 1290 ms | 32 ms | 40.66x | 7 MB |
| relayd | 2 files x 200 | 0.2 MB | 387 ms | 17 ms | 22.20x | 6 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
