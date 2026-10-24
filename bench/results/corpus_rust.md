| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 4622 | 3.0 MB | 2328 ms | 353 ms | 364 ms | 6.4x | 388 MB | 334 MB |
| mustache | 25 files x 8108 | 3.0 MB | 1422 ms | 418 ms | 292 ms | 4.9x | 552 MB | 244 MB |
| algol60 | 5 files x 1261 | 3.0 MB | 8382 ms | 494 ms | 443 ms | 18.9x | 196 MB | 142 MB |
| httpd | 1 files x 3778 | 3.0 MB | 4582 ms | 368 ms | 248 ms | 18.5x | 140 MB | 28 MB |
| relayd | 2 files x 3957 | 3.0 MB | 1338 ms | 182 ms | 147 ms | 9.1x | 108 MB | 44 MB |
| snmpd | 2 files x 5514 | 3.0 MB | 1217 ms | 154 ms | 143 ms | 8.5x | 39 MB | 29 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.34 on the host, hbnf aaf9aa9; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
