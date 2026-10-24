| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 370 ms | 370 ms | 1.00x | 425 MB | 416 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 235 ms | 113 ms | 2.08x | 215 MB | 130 MB | 1.66x |
| algol60 | 5 files x 12615 | 30.0 MB | 3286 ms | 2945 ms | 1.12x | 968 MB | 666 MB | 1.45x |
| bgpd | 4 files x 20000 | 19.7 MB | 665 ms | 588 ms | 1.13x | 398 MB | 277 MB | 1.44x |
| httpd | 1 files x 20000 | 15.9 MB | 420 ms | 377 ms | 1.11x | 221 MB | 110 MB | 2.00x |
| ntpd | 1 files x 20000 | 6.9 MB | 83 ms | 83 ms | 1.00x | 36 MB | 36 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 1359 ms | 733 ms | 1.85x | 1441 MB | 339 MB | 4.25x |
| relayd | 2 files x 20000 | 15.2 MB | 251 ms | 236 ms | 1.06x | 76 MB | 58 MB | 1.32x |
| snmpd | 2 files x 20000 | 10.9 MB | 180 ms | 165 ms | 1.09x | 73 MB | 57 MB | 1.28x |
| unwind | 1 files x 20000 | 4.7 MB | 66 ms | 66 ms | 1.01x | 18 MB | 16 MB | 1.14x |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 3.84 on the host, hbnf 4694beb; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
