| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 939 ms | 939 ms | 1.00x | 308 MB | 302 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 446 ms | 298 ms | 1.50x | 215 MB | 130 MB | 1.66x |
| algol60 | 5 files x 12615 | 30.0 MB | 4004 ms | 3699 ms | 1.08x | 975 MB | 662 MB | 1.47x |
| bgpd | 4 files x 20000 | 19.7 MB | 1336 ms | 1269 ms | 1.05x | 398 MB | 277 MB | 1.44x |
| httpd | 1 files x 20000 | 15.9 MB | 711 ms | 818 ms | 0.87x | 221 MB | 110 MB | 2.01x |
| ntpd | 1 files x 20000 | 6.9 MB | 99 ms | 100 ms | 1.00x | 36 MB | 36 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 1922 ms | 1315 ms | 1.46x | 1441 MB | 339 MB | 4.25x |
| relayd | 2 files x 20000 | 15.2 MB | 334 ms | 320 ms | 1.05x | 76 MB | 58 MB | 1.32x |
| snmpd | 2 files x 20000 | 10.9 MB | 212 ms | 199 ms | 1.06x | 73 MB | 57 MB | 1.28x |
| unwind | 1 files x 20000 | 4.7 MB | 70 ms | 70 ms | 0.99x | 18 MB | 16 MB | 1.15x |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
