| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 4622 | 3.0 MB | 1899 ms | 461 ms | 429 ms | 4.4x | 622 MB | 541 MB |
| mustache | 25 files x 8108 | 3.0 MB | 1417 ms | 422 ms | 297 ms | 4.8x | 552 MB | 244 MB |
| algol60 | 5 files x 1261 | 3.0 MB | 8746 ms | 498 ms | 446 ms | 19.6x | 196 MB | 142 MB |
| httpd | 1 files x 3778 | 3.0 MB | 4689 ms | 369 ms | 251 ms | 18.7x | 140 MB | 28 MB |
| relayd | 2 files x 3957 | 3.0 MB | 1373 ms | 187 ms | 149 ms | 9.2x | 108 MB | 44 MB |
| snmpd | 2 files x 5514 | 3.0 MB | 1238 ms | 155 ms | 144 ms | 8.6x | 39 MB | 28 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
