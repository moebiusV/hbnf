| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 551 ms | 541 ms | 1.02x | 308 MB | 302 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 291 ms | 169 ms | 1.72x | 215 MB | 130 MB | 1.66x |
| algol60 | 5 files x 12615 | 30.0 MB | 3843 ms | 3502 ms | 1.10x | 975 MB | 666 MB | 1.46x |
| bgpd | 4 files x 20000 | 19.7 MB | 789 ms | 695 ms | 1.13x | 398 MB | 277 MB | 1.44x |
| httpd | 1 files x 20000 | 15.9 MB | 472 ms | 456 ms | 1.03x | 221 MB | 110 MB | 2.00x |
| ntpd | 1 files x 20000 | 6.9 MB | 89 ms | 89 ms | 1.00x | 36 MB | 36 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 1591 ms | 951 ms | 1.67x | 1441 MB | 339 MB | 4.25x |
| relayd | 2 files x 20000 | 15.2 MB | 276 ms | 261 ms | 1.06x | 76 MB | 58 MB | 1.32x |
| snmpd | 2 files x 20000 | 10.9 MB | 190 ms | 178 ms | 1.07x | 73 MB | 57 MB | 1.28x |
| unwind | 1 files x 20000 | 4.7 MB | 66 ms | 67 ms | 0.99x | 18 MB | 16 MB | 1.14x |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.34 on the host, hbnf aaf9aa9; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
