| corpus | input | parsed | time, old layout | time, compact | speed-up | memory, old | memory, compact | saved |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| json | 26 files x 20000 | 13.0 MB | 180 ms | 187 ms | 0.96x | 270 MB | 265 MB | 1.02x |
| mustache | 25 files x 20000 | 7.4 MB | 72 ms | 58 ms | 1.25x | 90 MB | 48 MB | 1.88x |
| algol60 | 5 files x 12615 | 30.0 MB | 1775 ms | 1253 ms | 1.42x | 3075 MB | 1886 MB | 1.63x |
| bgpd | 4 files x 20000 | 19.7 MB | 519 ms | 471 ms | 1.10x | 381 MB | 277 MB | 1.38x |
| httpd | 1 files x 20000 | 15.9 MB | 333 ms | 304 ms | 1.09x | 239 MB | 106 MB | 2.25x |
| ntpd | 1 files x 20000 | 6.9 MB | 69 ms | 69 ms | 1.00x | 32 MB | 32 MB | 1.00x |
| pfctl | 7 files x 12717 | 30.0 MB | 955 ms | 618 ms | 1.55x | 812 MB | 306 MB | 2.65x |
| relayd | 2 files x 20000 | 15.2 MB | 252 ms | 224 ms | 1.12x | 86 MB | 61 MB | 1.42x |
| snmpd | 2 files x 20000 | 10.9 MB | 153 ms | 144 ms | 1.06x | 66 MB | 53 MB | 1.25x |
| unwind | 1 files x 20000 | 4.7 MB | 55 ms | 54 ms | 1.01x | 16 MB | 15 MB | 1.08x |

_Measured 2026-10-27 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 7.32 on the host, hbnf 56e8c78; gcc 14, byacc 20241231, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12.1 2026-08-18; best of up to 5 runs (two at least, fewer for a parser that takes seconds, so that no parser costs more than about 30 s), one process per run, `gcc -O2`._
