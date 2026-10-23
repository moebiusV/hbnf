| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 563 ms | 554 ms | 1.02x | 309 MB | 302 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 293 ms | 172 ms | 1.70x | 215 MB | 130 MB | 1.66x |
| algol60 | 5 files x 12615 | 30.0 MB | 3976 ms | 3684 ms | 1.08x | 975 MB | 666 MB | 1.46x |
| bgpd | 4 files x 20000 | 19.7 MB | 972 ms | 885 ms | 1.10x | 398 MB | 277 MB | 1.44x |
| httpd | 1 files x 20000 | 15.9 MB | 898 ms | 842 ms | 1.07x | 221 MB | 110 MB | 2.00x |
| ntpd | 1 files x 20000 | 6.9 MB | 150 ms | 151 ms | 0.99x | 36 MB | 36 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 2623 ms | 1748 ms | 1.50x | 1441 MB | 339 MB | 4.25x |
| relayd | 2 files x 20000 | 15.2 MB | 443 ms | 427 ms | 1.04x | 76 MB | 58 MB | 1.32x |
| snmpd | 2 files x 20000 | 10.9 MB | 215 ms | 203 ms | 1.06x | 73 MB | 57 MB | 1.28x |
| unwind | 1 files x 20000 | 4.7 MB | 72 ms | 72 ms | 1.00x | 18 MB | 16 MB | 1.14x |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.08 on the host, hbnf cd94a16; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
