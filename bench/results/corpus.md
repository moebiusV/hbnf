| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 552 ms | 543 ms | 1.02x | 308 MB | 302 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 294 ms | 172 ms | 1.71x | 215 MB | 130 MB | 1.66x |
| algol60 | 5 files x 12615 | 30.0 MB | 3919 ms | 3582 ms | 1.09x | 975 MB | 666 MB | 1.46x |
| bgpd | 4 files x 20000 | 19.7 MB | 943 ms | 857 ms | 1.10x | 398 MB | 277 MB | 1.44x |
| httpd | 1 files x 20000 | 15.9 MB | 566 ms | 540 ms | 1.05x | 221 MB | 110 MB | 2.00x |
| ntpd | 1 files x 20000 | 6.9 MB | 95 ms | 96 ms | 1.00x | 36 MB | 36 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 1746 ms | 1123 ms | 1.55x | 1441 MB | 339 MB | 4.25x |
| relayd | 2 files x 20000 | 15.2 MB | 307 ms | 288 ms | 1.06x | 76 MB | 58 MB | 1.32x |
| snmpd | 2 files x 20000 | 10.9 MB | 207 ms | 192 ms | 1.08x | 73 MB | 57 MB | 1.28x |
| unwind | 1 files x 20000 | 4.7 MB | 69 ms | 70 ms | 0.99x | 18 MB | 16 MB | 1.13x |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 5.81 on the host, hbnf 23fc853; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
