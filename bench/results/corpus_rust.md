| corpus | input | parsed | time before | time, lazy errors | time now (compact) | faster | memory, old layout | memory, compact |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 4622 | 3.0 MB | 3714 ms | 551 ms | 558 ms | 6.7x | 388 MB | 334 MB |
| mustache | 25 files x 8108 | 3.0 MB | 2203 ms | 623 ms | 444 ms | 5.0x | 552 MB | 244 MB |
| algol60 | 5 files x 1261 | 3.0 MB | 13825 ms | 744 ms | 650 ms | 21.3x | 196 MB | 142 MB |
| httpd | 1 files x 3778 | 3.0 MB | 7325 ms | 615 ms | 426 ms | 17.2x | 140 MB | 28 MB |
| relayd | 2 files x 3957 | 3.0 MB | 1481 ms | 282 ms | 242 ms | 6.1x | 108 MB | 44 MB |
| snmpd | 2 files x 5514 | 3.0 MB | 1457 ms | 163 ms | 155 ms | 9.4x | 39 MB | 29 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.08 on the host, hbnf cd94a16; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
