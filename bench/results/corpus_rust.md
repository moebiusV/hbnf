| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 4622 | 3.0 MB | 2315 ms | 349 ms | 360 ms | 6.4x | 388 MB | 334 MB |
| mustache | 25 files x 8108 | 3.0 MB | 1402 ms | 412 ms | 287 ms | 4.9x | 552 MB | 244 MB |
| algol60 | 5 files x 1261 | 3.0 MB | 8529 ms | 489 ms | 441 ms | 19.4x | 196 MB | 142 MB |
| httpd | 1 files x 3778 | 3.0 MB | 4574 ms | 364 ms | 249 ms | 18.4x | 140 MB | 28 MB |
| relayd | 2 files x 3957 | 3.0 MB | 1347 ms | 183 ms | 146 ms | 9.2x | 108 MB | 44 MB |
| snmpd | 2 files x 5514 | 3.0 MB | 1216 ms | 154 ms | 144 ms | 8.5x | 39 MB | 28 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.15 on the host, hbnf a42b9b6; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
