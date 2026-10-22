| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 576 ms | 595 ms | 0.97x | 308 MB | 302 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 307 ms | 193 ms | 1.59x | 215 MB | 130 MB | 1.66x |
| algol60 | 5 files x 12615 | 30.0 MB | 3991 ms | 3689 ms | 1.08x | 975 MB | 662 MB | 1.47x |
| bgpd | 4 files x 20000 | 19.7 MB | 1342 ms | 1271 ms | 1.06x | 398 MB | 286 MB | 1.39x |
| httpd | 1 files x 20000 | 15.9 MB | 704 ms | 812 ms | 0.87x | 221 MB | 110 MB | 2.01x |
| ntpd | 1 files x 20000 | 6.9 MB | 99 ms | 99 ms | 1.00x | 36 MB | 36 MB | 1.01x |
| pfctl | 7 files x 12717 | 30.0 MB | 1913 ms | 1388 ms | 1.38x | 1441 MB | 383 MB | 3.76x |
| relayd | 2 files x 20000 | 15.2 MB | 338 ms | 323 ms | 1.05x | 76 MB | 57 MB | 1.33x |
| snmpd | 2 files x 20000 | 10.9 MB | 215 ms | 202 ms | 1.06x | 73 MB | 61 MB | 1.19x |
| unwind | 1 files x 20000 | 4.7 MB | 69 ms | 70 ms | 1.00x | 18 MB | 18 MB | 1.00x |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.65 on the host, hbnf b27ed85; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
